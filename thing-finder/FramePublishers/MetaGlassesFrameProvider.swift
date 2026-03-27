/*
 * MetaGlassesFrameProvider.swift
 *
 * FrameProvider implementation for Meta glasses using the DAT SDK.
 *
 * Lightweight adapter that delegates to StreamSessionViewModel.
 * Responsibility: forward frames from the view model to the FrameProviderDelegate.
 */

import CoreMedia
import MWDATCamera
import MWDATCore
import UIKit

final class MetaGlassesFrameProvider: NSObject, FrameProvider {

  // MARK: - FrameProvider Protocol

  let previewView: UIView = UIView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .metaGlasses
  private(set) var isRunning: Bool = false

  // MARK: - Private

  private let streamSessionVM: StreamSessionViewModel
  private var frameObservationTask: Task<Void, Never>?

  private let previewImageView: UIImageView = {
    let iv = UIImageView()
    iv.contentMode = .scaleAspectFill
    iv.clipsToBounds = true
    return iv
  }()

  // MARK: - Init

  init(
    streamSessionViewModel: StreamSessionViewModel = MetaGlassesEnvironment.shared
      .streamSessionViewModel
  ) {
    self.streamSessionVM = streamSessionViewModel
    super.init()
    previewView.addSubview(previewImageView)
    previewImageView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      previewImageView.topAnchor.constraint(equalTo: previewView.topAnchor),
      previewImageView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
      previewImageView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
      previewImageView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
    ])
  }

  deinit {
    frameObservationTask?.cancel()
  }

  // MARK: - FrameProvider Methods

  func setupSession() {
    // Start observing frames from the view model
    frameObservationTask?.cancel()
    frameObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        if let frame = self.streamSessionVM.currentVideoFrame {
          self.previewImageView.image = frame
          // Convert UIImage back to CVPixelBuffer for the delegate
          if let pixelBuffer = frame.pixelBuffer() {
            self.delegate?.processFrame(self, buffer: pixelBuffer, depthAt: { _ in nil })
          }
        }
        try? await Task.sleep(nanoseconds: 33_000_000)  // ~30fps polling
      }
    }
  }

  func start() {
    guard !isRunning else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.streamSessionVM.handleStartStreaming()
      self.isRunning = true
      self.setupSession()
    }
  }

  func stop() {
    guard isRunning else { return }
    Task { @MainActor [weak self] in
      guard let self else { return }
      await self.streamSessionVM.stopStreaming()
      self.frameObservationTask?.cancel()
      self.frameObservationTask = nil
      self.isRunning = false
    }
  }

}

// MARK: - UIImage to CVPixelBuffer conversion

extension UIImage {
  fileprivate func pixelBuffer() -> CVPixelBuffer? {
    guard let cgImage = self.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height

    let attrs =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
      ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32ARGB,
      attrs,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
      )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
  }
}
