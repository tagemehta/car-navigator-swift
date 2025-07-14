//  VerifierService.swift
//  Wraps async LLM verification calls and feeds results into CandidateStore.

import Combine
import CoreVideo
import Foundation
import ImageIO
import UIKit

/// Lightweight protocol for DI/mocking
protocol VerifierService {
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect)
}

final class DefaultVerifierService: VerifierService {
  private let store: CandidateStore
  private let apiClient: LLMVerifier  // assumed existing
  private let imgUtils: ImageUtilities
  private var cancellables: Set<AnyCancellable> = []

  init(store: CandidateStore, apiClient: LLMVerifier, imgUtils: ImageUtilities) {
    self.store = store
    self.apiClient = apiClient
    self.imgUtils = imgUtils
  }

  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect
  ) {
    // Fire off new verifications for candidates still unknown
    let pending = store.candidates.values.filter { $0.matchStatus == .unknown }
    var fullImage: CGImage?
    for cand in pending {
      if self.apiClient.targetTextDescription == "" {
        self.store.update(id: cand.id) { c in
          c.matchStatus = .matched
        }
        continue
      }
      // Convert normalised Vision rect → image coordinates
      let (imageRect, _) = imgUtils.unscaledBoundingBoxes(
        for: cand.lastBoundingBox,
        imageSize: imageSize,
        viewSize: viewBounds.size,
        orientation: orientation)
      // Clamp rect inside buffer bounds
      let safeRect = CGRect(
        x: max(0, min(imageRect.origin.x, imageSize.width)),
        y: max(0, min(imageRect.origin.y, imageSize.height)),
        width: max(0, min(imageRect.width, imageSize.width - imageRect.origin.x)),
        height: max(0, min(imageRect.height, imageSize.height - imageRect.origin.y))
      )

      // Convert buffer → CGImage once per tick

      fullImage = fullImage ?? imgUtils.cvPixelBuffertoCGImage(buffer: pixelBuffer)
      guard let cropped = fullImage!.cropping(to: safeRect)
      else { continue }
      let uiImage = UIImage(cgImage: cropped)
      guard let jpegData = uiImage.jpegData(compressionQuality: 1) else { continue }
      self.store.update(id: cand.id) { c in
        c.matchStatus = .waiting
      }
      apiClient.verify(imageData: jpegData.base64EncodedString())
        .sink { completion in
          if case .failure(let err) = completion { print("LLM verify error: \(err)") }
        } receiveValue: { [weak self] matched in
          guard let self else { return }
          self.store.update(id: cand.id) { c in
            c.matchStatus = matched ? .matched : .rejected
          }
        }
        .store(in: &cancellables)
    }
  }
}
