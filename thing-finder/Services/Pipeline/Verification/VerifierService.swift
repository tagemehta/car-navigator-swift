/// VerifierService
/// ----------------
/// Frame-driven orchestrator called once per frame by `FramePipelineCoordinator`.
///
/// Responsibilities:
///   1. Filter candidates needing verification (.unknown status).
///   2. Rate-limit and per-candidate throttle.
///   3. Crop the candidate from the pixel buffer.
///   4. Delegate to `VerifierSelector` which picks TrafficEye or LLM.
///   5. Update `CandidateStore` with the result (match / reject / retry).
///   6. OCR pass for license-plate verification (when enabled).
///
/// Counter management (attempt escalation, counter resets) lives in
/// `VerifierSelector` – this class only increments the active counter on failure.

import Combine
import CoreVideo
import Foundation
import UIKit
import Vision

public final class VerifierService: VerifierServiceProtocol {

  private let selector: VerifierSelector
  internal let imgUtils: ImageUtilities
  internal let verificationConfig: VerificationConfig
  internal let ocrEngine: OCREngine
  private var cancellables: Set<AnyCancellable> = []
  /// Timestamp of the most recent *batch* of verify() requests (i.e., the last tick that sent one or more verify calls).
  private var lastVerifyBatch: Date = .distantPast
  /// Minimum interval between successive batches of verify() requests.
  private let minVerifyInterval: TimeInterval = 1  // seconds

  init(
    targetTextDescription: String,
    imgUtils: ImageUtilities,
    config: VerificationConfig,
    ocrEngine: OCREngine = VisionOCREngine()
  ) {
    self.selector = VerifierSelector(
      targetTextDescription: targetTextDescription,
      config: config
    )
    self.imgUtils = imgUtils
    self.verificationConfig = config
    self.ocrEngine = ocrEngine
  }

  /// Called every frame by `FramePipelineCoordinator`.
  public func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    store: CandidateStore
  ) {
    let now = Date()
    // Thread-safe read copy of current candidates
    let candidatesSnapshot = store.snapshot()
    let pendingUnknown = candidatesSnapshot.values.filter { $0.matchStatus == .unknown }

    // // Include stale partial/full candidates for re-verification
    // Split candidates into ones we can auto-match (no text description) and ones needing verification.
    var toVerify: [Candidate] = []
    // toVerify.append(contentsOf: staleVerified)  // Disabled re-verification

    // Check if we have a target description to verify against
    let hasTargetDescription = !(selector.targetTextDescription.isEmpty)

    if !hasTargetDescription {
      for cand in pendingUnknown {
        store.update(id: cand.id) { $0.matchStatus = .full }
      }
    } else {
      toVerify.append(contentsOf: pendingUnknown)
    }
    guard
      !toVerify.isEmpty || !store.snapshot().values.filter({ $0.matchStatus == .partial }).isEmpty
    else { return }

    // --------- OCR retry pass (only when OCR enabled)
    var fullImage: CGImage?
    if self.verificationConfig.shouldRunOCR {
      let partials = store.snapshot().values.filter {
        $0.matchStatus == .partial && $0.ocrAttempts < self.verificationConfig.maxOCRRetries
      }
      if !partials.isEmpty {
        fullImage = imgUtils.cvPixelBuffertoCGImage(buffer: pixelBuffer)
        for cand in partials {
          self.enqueueOCR(
            for: cand, fullImage: fullImage!, imageSize: imageSize, orientation: orientation,
            store: store)
        }
      }
    }
    // Rate-limit: if the previous batch was too recent, skip this tick entirely.
    guard now.timeIntervalSince(lastVerifyBatch) >= minVerifyInterval else {
      return
    }

    fullImage = fullImage ?? imgUtils.cvPixelBuffertoCGImage(buffer: pixelBuffer)

    lastVerifyBatch = now
    for cand in toVerify {
      // ---------------- Per-candidate throttling ----------------
      DebugPublisher.shared.info(
        "[Verifier][\(cand.id.uuidString.suffix(8))] Considering candidate; bestView=\(cand.view), lastMMR=\(cand.lastMMRTime.timeIntervalSince1970)"
      )

      // Skip verification if the candidate's bounding box covers less than 15% of the frame.
      // `lastBoundingBox` is already normalised to [0,1] coordinates so width*height gives
      // the fraction of image area occupied.
      let bboxArea = cand.lastBoundingBox.width * cand.lastBoundingBox.height
      let minAreaThreshold: CGFloat = 0.01  // 1% of the image
      if bboxArea < minAreaThreshold {
        let _ =
          "Candidate \(cand.id.uuidString.suffix(8)) skipped – bbox too small (\(String(format: "%.1f", bboxArea * 100))%)"
        //        print("[Verifier] \(message)")
        //        DebugPublisher.shared.info(message)
        continue
      }

      // Skip verification if bounding box is significantly taller than it is wide.
      // Allow roughly square boxes (front/rear views) but reject tall portrait shapes.
      let aspectRatio = cand.lastBoundingBox.height / max(cand.lastBoundingBox.width, 0.0001)
      let maxTallness: CGFloat = 3  // height cannot exceed 300% of width
      if aspectRatio > maxTallness {
        let message =
          "Candidate \(cand.id.uuidString.suffix(8)) skipped – bbox too tall (h/w=\(String(format: "%.1f", aspectRatio)))"
        DebugPublisher.shared.warning("[Verifier] \(message)")
        continue
      }

      if now.timeIntervalSince(cand.lastMMRTime) < verificationConfig.perCandidateMMRInterval {
        // Skip re-verify until per-candidate interval passes.
        let message = "Candidate \(cand.id.uuidString.suffix(8)) skipped – MMR throttled"
        DebugPublisher.shared.info("[Verifier] \(message)")
        continue
      }

      // Convert normalized box → pixel rect using ImageUtilities
      let (imageRect, _) = imgUtils.unscaledBoundingBoxes(
        for: cand.lastBoundingBox,
        imageSize: imageSize,
        viewSize: imageSize,  // view size irrelevant here
        orientation: orientation
      )
      guard let crop = fullImage!.cropping(to: imageRect) else { continue }

      let img = UIImage(cgImage: crop, scale: 1.0, orientation: UIImage.Orientation(orientation))
      // For first-time verification show .waiting; for periodic re-verification keep current status to avoid extra speech.
      if cand.matchStatus == .unknown {
        store.update(id: cand.id) { $0.matchStatus = .waiting }
        TelemetryService.shared.incrementCandidates(id: cand.id)
      }

      let verifyStartTime = Date()
      selector.verify(image: img, candidate: cand, store: store)
        .sink { completion in
          switch completion {
          case .finished:
            break
          case .failure(let error):
            DebugPublisher.shared.error(
              "[Verifier][\(cand.id.uuidString.suffix(8))] Pipeline failed with error: \(error.localizedDescription)"
            )
            // Handle verification failure with proper error mapping
            let rejectReason: RejectReason
            if let twoStepError = error as? TwoStepError {
              switch twoStepError {
              case .noToolResponse, .networkError:
                rejectReason = .apiError
              case .occluded:
                rejectReason = .unclearImage
              case .lowConfidence:
                rejectReason = .lowConfidence
              }
            } else {
              rejectReason = .apiError
            }

            store.update(id: cand.id) {
              $0.matchStatus = .unknown
              $0.rejectReason = rejectReason
            }
          }
        } receiveValue: { [weak self] (outcome, strategyName) in
          guard let self = self else { return }

          // -------- Post-verification bookkeeping --------
          let latency = Date().timeIntervalSince(verifyStartTime)

          let telemetryOutcome: String
          if outcome.isMatch {
            telemetryOutcome = "match"
          } else if let reason = outcome.rejectReason, reason.isRetryable {
            telemetryOutcome = "retry"
          } else {
            telemetryOutcome = "reject"
          }
          TelemetryService.shared.recordVerificationAttempt(
            verifier: strategyName,
            outcome: telemetryOutcome,
            durationMs: Int(latency * 1000),
            rejectReason: outcome.rejectReason?.rawValue
          )

          DebugPublisher.shared.info(
            "[Verifier][\(cand.id.uuidString.suffix(8))] Result: strategy=\(strategyName), match=\(outcome.isMatch), view=\(String(describing: outcome.vehicleView)), score=\(String(describing: outcome.viewScore)), reason=\(String(describing: outcome.rejectReason?.rawValue)), latency=\(String(format: "%.3f", latency))s"
          )

          // Update view and timing information
          store.update(id: cand.id) { c in
            if let v = outcome.vehicleView {
              c.view = v
              c.viewScore = outcome.viewScore ?? 0
            }
            // Update MMR time for TrafficEye strategies
            if strategyName.contains("TrafficEye") {
              c.lastMMRTime = now
            }
          }

          // Update attempt counters based on strategy type
          if !outcome.isMatch {
            store.update(id: cand.id) {
              if strategyName.contains("TrafficEye") {
                $0.verificationTracker.trafficAttempts += 1
              } else {
                $0.verificationTracker.llmAttempts += 1
              }
            }
          }

          if outcome.isMatch {
            DebugPublisher.shared.info(
              "[Verifier][\(cand.id.uuidString.suffix(8))] Matched candidate")
            let currentStatus = store[cand.id]?.matchStatus
            if currentStatus == .lost || currentStatus == nil {
              let reason = currentStatus == nil ? "removed" : "lost"
              DebugPublisher.shared.warning(
                "[Verifier][\(cand.id.uuidString.suffix(8))] Match returned but candidate was \(reason) during API call (latency \(String(format: "%.3f", latency))s)"
              )
              TelemetryService.shared.recordMatchDiscarded(
                reason: reason, latencyMs: Int(latency * 1000))
            }
            store.update(id: cand.id) {
              $0.detectedDescription = outcome.description
              $0.lastVerified = Date()
            }
            if !self.verificationConfig.shouldRunOCR || outcome.isPlateMatch {
              DebugPublisher.shared.info(
                "[Verifier][\(cand.id.uuidString.suffix(8))] State before update: \(store[cand.id]?.matchStatus ?? .unknown). Updating to .full."
              )
              store.update(id: cand.id) {
                $0.matchStatus = .full
                $0.lastVerified = Date()
              }
              DebugPublisher.shared.success("Match: \(outcome.description)")
              return
            }
            // Promote to partial and begin OCR verification
            DebugPublisher.shared.info(
              "[Verifier][\(cand.id.uuidString.suffix(8))] State before update: \(store[cand.id]?.matchStatus ?? .unknown). Matched, but requires OCR. Updating to .partial."
            )
            store.update(id: cand.id) {
              $0.matchStatus = .partial
              $0.detectedDescription = outcome.description
              $0.lastVerified = Date()
            }
            self.enqueueOCR(
              for: cand, fullImage: fullImage!, imageSize: imageSize, orientation: orientation,
              store: store)
          } else {
            store.update(id: cand.id) {
              // Convert string rejectReason to enum
              let reason = outcome.rejectReason

              // Check if the reason is retryable
              if let reason = reason, reason.isRetryable {
                DebugPublisher.shared.info(
                  "[Verifier][\(cand.id.uuidString.suffix(8))] State before update: \($0.matchStatus). Retryable reason: \(reason). Updating to .unknown."
                )
                // Retryable reason - keep searching so candidate will be retried
                $0.matchStatus = .unknown
              } else if reason != nil {
                // Hard reject reason
                DebugPublisher.shared.info(
                  "[Verifier][\(cand.id.uuidString.suffix(8))] State before update: \($0.matchStatus). Hard reject reason: \(reason!). Updating to .rejected."
                )
                $0.matchStatus = .rejected
              }

              $0.rejectReason = reason
              $0.detectedDescription = outcome.description
            }
          }
        }
        .store(in: &cancellables)
    }

  }
}
