//  VisionTracker.swift
//  Encapsulates VNTrackObjectRequest lifecycle. Each frame, updates requests
//  and writes the latest bounding boxes back into CandidateStore.
//  Heavy Vision work stays off main thread; store mutations are dispatched to
//  the main queue.

import CoreVideo
import Foundation
import Vision

/// Protocol so we can swap in a mock for unit tests
protocol VisionTracker {
  /// Call once per frame with the current camera pixelBuffer & orientation.
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation)
}

final class DefaultVisionTracker: VisionTracker {
  private let store: CandidateStore
  private let imgUtils: ImageUtilities
  private let queue = DispatchQueue(label: "vision.tracker")
  private let sequenceHandler = VNSequenceRequestHandler()

  init(store: CandidateStore, imgUtils: ImageUtilities) {
    self.store = store
    self.imgUtils = imgUtils
  }

  func tick(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
    queue.async { [weak self] in
      guard let self else { return }
      // Perform VNTrackObjectRequests with a sequence handler
      let activeRequests = self.store.candidates.values.map { $0.trackingRequest }
      guard !activeRequests.isEmpty else { return }
      do {
        try self.sequenceHandler.perform(
          activeRequests,
          on: pixelBuffer,
          orientation: orientation)
        for (key, value) in self.store.candidates {
          if value.trackingRequest.isLastFrame {
            self.store.remove(id: key)
          }
        }
      } catch {
        for (key, value) in self.store.candidates {
          if value.trackingRequest.isLastFrame {
            self.store.remove(id: key)
          }
        }
        print("VisionTracker error: \(error)")
      }

      // Write updated boxes back to store on main thread
      DispatchQueue.main.async {
        for candidate in self.store.candidates.values {

          if let obs = candidate.trackingRequest.results?.first as? VNDetectedObjectObservation {
            self.store.update(id: candidate.id) { c in
              c.lastBoundingBox = obs.boundingBox
            }
          }

        }
      }

    }
  }
}
