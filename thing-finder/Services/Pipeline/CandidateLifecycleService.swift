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
    detections: [Detection],
    store: CandidateStore
  ) -> Bool
}

// MARK: – Concrete implementation

public final class CandidateLifecycleService: CandidateLifecycleServiceProtocol {

  private let imgUtils: ImageUtilities
  /// Consecutive frames without detection overlap before candidate is removed/lost.
  /// At 30fps, 90 frames = ~3s. Provides tolerance for brief occlusions and detection flicker.
  private let missThreshold: Int
  /// How long (seconds) to keep rejected candidates before removing them.
  private let rejectCooldown: TimeInterval
  private let compass: CompassProvider
  /// Maximum number of simultaneous non-lost candidates. Prevents unbounded Vision tracker
  /// and embedding memory growth in dense environments (e.g. parking lots).
  /// At 10 candidates, tracking stays under ~20ms/frame on A15-class hardware,
  /// leaving headroom for detection, drift repair, and UI. .partial, .full, and .lost
  /// candidates are exempt and never evicted — this cap only applies at ingest time.
  private let candidateCap: Int

  public init(
    imgUtils: ImageUtilities = .shared,
    missThreshold: Int = 90,
    rejectCooldown: TimeInterval = 10,
    compass: CompassProvider = CompassHeading.shared,
    candidateCap: Int = 10
  ) {
    self.imgUtils = imgUtils
    self.missThreshold = missThreshold
    self.rejectCooldown = rejectCooldown
    self.compass = compass
    self.candidateCap = candidateCap
  }

  /// Eviction priority order for candidates when the store is at cap.
  /// Higher value = evicted first.
  private func evictionPriority(for status: MatchStatus) -> Int {
    switch status {
    case .rejected: return 2
    case .unknown: return 1
    case .waiting: return 0
    case .partial, .full, .lost: return -1  // never evicted
    }
  }

  public func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    detections: [Detection],
    store: CandidateStore
  ) -> Bool {

    // 1. Optionally ingest detections (skip when an active match exists)
    if !store.hasActiveMatch {
      var cgImage: CGImage?
      for det in detections {
        // Use the stored observation from the Detection wrapper to create tracking request
        guard let observation = det.observation else {
          continue
        }

        let bbox = det.boundingBox
        guard !store.containsDuplicateOf(bbox) else { continue }

        // Enforce candidate cap. Count only non-lost candidates — .lost candidates
        // hold recovered match state and must not be displaced by new detections.
        let nonLost = store.candidates.values.filter { $0.matchStatus != .lost }
        if nonLost.count >= candidateCap {
          // Find the best eviction candidate: highest missCount wins; ties broken by
          // status priority (.rejected > .unknown > .waiting). .partial/.full/.lost
          // are never evicted.
          let evictable = nonLost.filter { evictionPriority(for: $0.matchStatus) >= 0 }
          guard
            let evictTarget = evictable.max(by: { a, b in
              if a.missCount != b.missCount { return a.missCount < b.missCount }
              return evictionPriority(for: a.matchStatus) < evictionPriority(for: b.matchStatus)
            })
          else {
            // Store is full of protected candidates (.partial/.full) — skip detection.
            continue
          }
          DebugPublisher.shared.info(
            "[CandidateLifecycleService] Cap reached (\(candidateCap)): evicting \(evictTarget.id.uuidString.suffix(8)) status=\(evictTarget.matchStatus) missCount=\(evictTarget.missCount)"
          )
          store.remove(id: evictTarget.id)
        }

        // Create Tracking Request wrapper
        let visionReq = VNTrackObjectRequest(detectedObjectObservation: observation)
        visionReq.trackingLevel = .accurate
        let trackingRequest = TrackingRequest(from: visionReq)

        // Lazily create cgImage only when needed
        if cgImage == nil {
          cgImage = imgUtils.cvPixelBuffertoCGImage(buffer: pixelBuffer)
        }

        // Compute Embedding
        let embedding = EmbeddingComputer.compute(
          cgImage: cgImage!,
          boundingBox: bbox,
          orientation: orientation,
          imageSize: imageSize
        )

        // Create and upsert the candidate
        let newCandidate = Candidate(
          trackingRequest: trackingRequest,
          boundingBox: bbox,
          embedding: embedding
        )
        store.upsert(newCandidate)
      }
    }

    // 2. Enforce only one matched candidate
    store.pruneToSingleMatched()
    var isLost = false
    // 3. Update missCount + drop stale
    let snapshot = store.snapshot()
    let direction = compass.degrees  // initialize the direction for this frame
    for (id, cand) in snapshot {
      // Check reject cooldown FIRST (before any updates that change lastUpdated)
      if cand.matchStatus == .rejected,
        Date().timeIntervalSince(cand.lastUpdated) >= rejectCooldown
      {
        store.remove(id: id)
        continue
      }

      let overlaps = detections.contains { det in
        det.boundingBox.iou(with: cand.lastBoundingBox) > 0.1
      }
      if overlaps {
        store.update(id: id) {
          $0.missCount = 0
          $0.degrees = direction
        }
      } else {
        store.update(id: id) { $0.missCount += 1 }
        if let updated = store[id] {
          // Drop if missed too many frames
          if updated.missCount >= missThreshold {
            if updated.isMatched { isLost = true }
            if updated.matchStatus == .full {  // if the lost candidate was a full match change its info to lost
              store.update(id: id) { $0.matchStatus = .lost }
              continue
            } else if updated.matchStatus != .lost {
              DebugPublisher.shared.info(
                "[CandidateLifecycleService] Removing candidate \(id) with matchStatus: \(updated.matchStatus)"
              )
              store.remove(id: id)
              continue
            }
          }
        }
      }
    }

    return isLost
  }
}
