//  DriftRepairService.swift
//  thing-finder
//
//  ---------------------------------------------------------------------------
//  DriftRepairService
//  ---------------------------------------------------------------------------
//  Fixes the inevitable drift that accumulates when relying solely on Vision
//  `VNTrackObjectRequest`s. Every *N* frames (`repairStride`, default 15) it will:
//
//  1. For each *active* `Candidate` retrieve its last bounding box & embedding.
//  2. Find the best matching detection (IoU & cosine-similarity thresholds).
//  3. If a match is found, snap the candidate’s `trackingRequest` back onto the
//     detection observation and reset `missCount`.
//  4. If **no** match is found the candidate is untouched – the
//     `CandidateLifecycleService` will eventually mark it as lost.
//
//  Algorithm details:
//  • Cosine similarity of feature-print embeddings must exceed `simThreshold` (default 0.901).
//  • Embeddings are generated lazily and cached for the current frame to avoid
//    duplicate computation.
//
//  Threading: `tick` is designed to run on a background queue; the only store
//  mutation is through `CandidateStore.update`, which is dispatched back to the
//  main queue to maintain SwiftUI consistency.
//
//  Performance: With the defaults the service costs ~2–3 ms on an A16 for a
//  frame with <10 candidates.  Tune `repairStride` to trade accuracy for FPS.
//

import CoreGraphics
import CoreVideo
import Foundation
import Vision

final class DriftRepairService: DriftRepairServiceProtocol {

  // MARK: Dependencies
  private let imageUtils: ImageUtilities

  // MARK: Config
  private let repairStride: Int
  private let simThreshold: Float
  private var frameCounter: Int = 0

  init(
    imageUtils: ImageUtilities = ImageUtilities(),
    repairStride: Int = 15,
    simThreshold: Float = 0.90
  ) {
    self.imageUtils = imageUtils
    self.repairStride = repairStride
    self.simThreshold = simThreshold
  }

  // MARK: DriftRepairService
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    detections: [VNRecognizedObjectObservation],
    store: CandidateStore
  ) {
    frameCounter += 1
    guard frameCounter % repairStride == 0 else { return }
    let snapshot = store.snapshot()
    guard !snapshot.isEmpty else { return }

    // ---------------------------------------------------------------------
    // Per-frame cache: detection UUID → (bboxImageRect, embedding)
    // ---------------------------------------------------------------------
    var embedCache: [UUID: (CGRect, VNFeaturePrintObservation)] = [:]
    var remainingDetections = detections
    let fullCG = imageUtils.cvPixelBuffertoCGImage(buffer: pixelBuffer)
    // For each candidate attempt to find a better detection.
    for candidate in snapshot.values {
      guard
        let best = bestMatch(
          for: candidate,
          in: &remainingDetections,
          cgImage: fullCG,
          orientation: orientation,
          embedCache: &embedCache
        )
      else {
        store.update(id: candidate.id) { $0.lastBoundingBox = .zero }  // this is marking for destruction
        continue
      }

      // Replace tracking request & bbox
      let newRequest = VNTrackObjectRequest(detectedObjectObservation: best)
      newRequest.trackingLevel = .accurate

      // Fetch embedding from cache (guaranteed present after bestMatch)
      let cached = embedCache[best.uuid]!

      store.update(id: candidate.id) { cand in
        cand.trackingRequest = newRequest
        cand.lastBoundingBox = best.boundingBox
        cand.embedding = cached.1
      }
    }
  }

  // MARK: - Helpers
  private func bestMatch(
    for candidate: Candidate,
    in detections: inout [VNRecognizedObjectObservation],
    cgImage: CGImage,
    orientation: CGImagePropertyOrientation,
    embedCache: inout [UUID: (CGRect, VNFeaturePrintObservation)]
  ) -> VNRecognizedObjectObservation? {
    guard !detections.isEmpty else { return nil }

    var best: VNRecognizedObjectObservation?
    var bestScore: Float = 0
    for (_, det) in detections.enumerated().reversed() {  // iterate reversed so we can remove easily

      // Embedding similarity (cache heavy work)
      var sim: Float = 0
      if let candEmb = candidate.embedding {
        // Retrieve or compute embedding for this detection
        if embedCache[det.uuid] == nil {
          let W = cgImage.width
          let H = cgImage.height
          let (imageRect, _) = imageUtils.unscaledBoundingBoxes(
            for: det.boundingBox,
            imageSize: CGSize(width: W, height: H),
            viewSize: CGSize(width: W, height: H),
            orientation: orientation
          )
          if let crop = cgImage.cropping(to: imageRect) {
            if let emb = try? VNGenerateImageFeaturePrintRequest.computeFeaturePrint(cgImage: crop)
            {
              embedCache[det.uuid] = (imageRect, emb)
            }
          }
        }
        if let emb = embedCache[det.uuid]?.1 {
          sim = (try? candEmb.cosineSimilarity(to: emb)) ?? 0
        }
      }
      // Combine similarity with center-distance penalty
      /*let candCenter = CGPoint(x: candidate.lastBoundingBox.midX, y: candidate.lastBoundingBox.midY)
      let detCenter = CGPoint(x: det.boundingBox.midX, y: det.boundingBox.midY)
      let dx = candCenter.x - detCenter.x
      let dy = candCenter.y - detCenter.y
      let centerDist = sqrt(dx * dx + dy * dy)
      let maxDist: CGFloat = 0.40  // ~40 % of normalized space
      */
      // Embedding and center thresholds both individually have to be passed
      // Score then combines to find best match
      // Temporarily getting rid of center threshold
      // because it introduces noise for semi-quick movements
    

      let score = sim
      if sim > simThreshold && score > bestScore {
        bestScore = score
        best = det
      }
      // Early exit if perfect match
      if bestScore >= 0.99 { break }
    }
    if let best = best, let idx = detections.firstIndex(of: best) {
      detections.remove(at: idx)
      return best
    }
    return nil
  }
}

// MARK: - VNGenerateImageFeaturePrintRequest convenience

extension VNGenerateImageFeaturePrintRequest {
  fileprivate static func computeFeaturePrint(cgImage: CGImage) throws -> VNFeaturePrintObservation
  {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let req = VNGenerateImageFeaturePrintRequest()
    try handler.perform([req])
    guard let obs = req.results?.first as? VNFeaturePrintObservation else {
      throw FeaturePrintSimilarityError.cannotCompute
    }
    return obs
  }
}
