//  CandidateLifecycleService.swift
//  thing-finder
//
//  ---------------------------------------------------------------------------
//  CandidateLifecycleService
//  ---------------------------------------------------------------------------
//  A *stateless* (frame-local) helper that owns **all** candidate life-cycle
//  responsibilities so `FramePipelineCoordinator` can remain a thin
//  orchestrator.
//
//  High-level duties per frame:
//  • *Ingest* each fresh `VNRecognizedObjectObservation`:
//    – Prevent duplicates (IoU + centre-distance).
//    – Create & start a `VNTrackObjectRequest` so Vision continues updating the
//      bounding box across future frames.
//    – Crop the pixel buffer and compute an initial  feature-print embedding
//      via `EmbeddingComputer` (used by drift-repair & verifier).
//    – Insert a fully-initialised `Candidate` into `CandidateStore`.
//  • *Enforce* the **single-winner invariant** – at most one candidate is ever
//    in the `.matched` state (latest winner wins).
//  • *Book-keep* `missCount` for out-of-frame handling and purge any candidate
//    that exceeds the `missThreshold` (default: 5 consecutive misses).
//
//  The service returns a `Bool` indicating whether all candidates were removed
//  this frame, allowing the coordinator to emit a `.lost` navigation event and
//  reset any downstream state.
//
//  Thread-safety: callers *must* invoke `tick` on the **main thread** because it
//  mutates `@Published` state inside `CandidateStore`. Heavy Vision / CoreML
//  work (embedding computation) happens off-thread before the call.
//
//  Usage example (inside `FramePipelineCoordinator.process`):
//  ```swift
//  let lost = lifecycle.tick(pixelBuffer: pb,
//                            orientation: orient,
//                            imageSize: imgSize,
//                            detections: detections,
//                            store: store)
//  if lost { nav.handle(.lost, box: nil, distanceMeters: nil) }
//  ```
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

// MARK: – Protocol

public protocol CandidateLifecycleServiceProtocol {
  /// Performs ingest + lifecycle update.
  /// - Returns: `true` when **all** candidates were dropped this frame (lost).
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    detections: [VNRecognizedObjectObservation],
    store: CandidateStore
  ) -> Bool
}

// MARK: – Concrete implementation

public final class CandidateLifecycleService: CandidateLifecycleServiceProtocol {

  private let imgUtils: ImageUtilities
  private let missThreshold: Int
  private let rejectCooldown: TimeInterval

  public init(imgUtils: ImageUtilities = .shared,
              missThreshold: Int = 5,
              rejectCooldown: TimeInterval = 10) {
    self.imgUtils = imgUtils
    self.missThreshold = missThreshold
    self.rejectCooldown = rejectCooldown
  }

  public func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    detections: [VNRecognizedObjectObservation],
    store: CandidateStore
  ) -> Bool {

    // 1. Optionally ingest detections (skip when an active match exists)
    if !store.hasActiveMatch {
      var cgImage: CGImage?
      for det in detections {
        if cgImage == nil {
          cgImage = ImageUtilities.shared.cvPixelBuffertoCGImage(buffer: pixelBuffer)
        }
        _ = store.upsert(
          observation: det,
          cgImage: cgImage!,
          imageSize: imageSize,
          orientation: orientation
        )
      }
    }

    // 2. Enforce only one matched candidate
    store.pruneToSingleMatched()
    var isLost = false
    // 3. Update missCount + drop stale
    let snapshot = store.snapshot()
    for (id, cand) in snapshot {
      let overlaps = detections.contains { det in
        det.boundingBox.iou(with: cand.lastBoundingBox) > 0.1
      }
      if overlaps {
        store.update(id: id) { $0.missCount = 0 }
      } else {
        store.update(id: id) { $0.missCount += 1 }
        if let updated = store[id] {
          // Drop if missed too many frames
          if updated.missCount >= missThreshold {
            if updated.isMatched { isLost = true }
            store.remove(id: id)
            continue
          }
          // Drop after reject cooldown elapsed
          if updated.matchStatus == .rejected,
             Date().timeIntervalSince(updated.lastUpdated) >= rejectCooldown {
            store.remove(id: id)
            continue
          }
        }
      }
    }

    return isLost
  }
}
