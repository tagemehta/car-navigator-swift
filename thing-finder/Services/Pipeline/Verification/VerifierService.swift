/// VerifierService
/// --------------
/// Frame-driven orchestrator that decides **which verifier to call – TrafficEye or LLM –**
/// and applies the result back onto each `Candidate`.
///
/// ### Core ideas
/// • **Cost & latency balancing** – TrafficEye (fast, expensive, view-aware) first; LLM (slow, cheap,
///   view-agnostic) second.
/// • **Escalation loop** – The pipeline now _cycles indefinitely_ between the two engines using
///   **durable attempt counters**:
///   * `trafficAttempts` – consecutive failed TrafficEye calls.
///   * `llmAttempts`      – consecutive failed LLM calls.
///   When the active engine exceeds its limit the other engine is selected **and the opposite
///   counter is reset**, allowing the process to loop forever until a match or hard reject.
///
/// ### High-level flow per `tick(...)`
/// 1. Snapshot candidates from the shared `CandidateStore`.
/// 2. Determine which candidates are due for (re)verification.
/// 3. For each candidate choose the engine via `VerificationPolicy.nextKind(for:)`.
/// 4. **Reset the opposite counter** (implemented inside `VerifierService` just before calling).
/// 5. Call the chosen verifier asynchronously.
/// 6. Record success → `.matched`; on failure increment the active counter and keep looping.
///
/// ### Attempt limits (see `VerificationPolicy`)
/// ```
/// TrafficEye escalation:   side-view after 1 fail, any view after 3 fails
/// LLM fallback to TE:      after 2 consecutive LLM failures
/// ```
/// These constants can be tuned without touching `VerifierService`.
///
/// Threading: All verification calls run off-main; `CandidateStore` is thread-safe so updates are
/// posted directly from Combine sinks.
///
/// Dependencies injected:
/// * `TrafficEyeVerifier`, `TwoStepVerifier` (LLM)
/// * `ImageUtilities` – bounding-box helpers
/// * `OCREngine` – licence-plate verification
///
/// Created by Tage Mehta – updated 2025-08-06 to document the continuous TE ↔︎ LLM loop.
//
//  DefaultVerifierService.swift
//  thing-finder
//
//  Created as part of the state-machine refactor. Wraps asynchronous LLM
//  verification calls and updates the `CandidateStore` with the results.
//
//  NOTE: VSCode may show unresolved import warnings – they compile fine in
//  Xcode as per user guidance.

import Combine
import CoreVideo
import Foundation
import UIKit
import Vision

public final class VerifierService: VerifierServiceProtocol {
  /// Strategy manager for handling verification
  private let strategyManager: VerificationStrategyManager
  
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
    let factory = VerificationStrategyFactory(config: config)
    self.strategyManager = factory.createStrategyManager(targetTextDescription: targetTextDescription)
    self.imgUtils = imgUtils
    self.verificationConfig = config
    self.ocrEngine = ocrEngine
  }
  
  /// Legacy initializer for backwards compatibility
  init(
    verifier: ImageVerifier, 
    imgUtils: ImageUtilities, 
    config: VerificationConfig,
    ocrEngine: OCREngine = VisionOCREngine()
  ) {
    let factory = VerificationStrategyFactory(config: config)
    self.strategyManager = factory.createStrategyManager(targetTextDescription: verifier.targetTextDescription)
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
    // let staleVerified = candidatesSnapshot.values.filter {
    //   ($0.matchStatus == .partial || $0.matchStatus == .full)
    //     && (now.timeIntervalSince($0.lastVerified ?? $0.createdAt)
    //       >= self.verificationConfig.reverifyInterval)
    // }
    // Split candidates into ones we can auto-match (no text description) and ones needing verification.
    var toVerify: [Candidate] = []
    // toVerify.append(contentsOf: staleVerified)  // Disabled re-verification
    
    // Check if we have a target description to verify against
    let hasTargetDescription = !strategyManager.strategies.isEmpty && 
                              !(strategyManager.targetTextDescription?.isEmpty ?? true)
    
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
      print(
        "[Verifier] Considering candidate \(cand.id); bestView=\(cand.view); lastMMR=\(cand.lastMMRTime.timeIntervalSince1970)"
      )

      // Skip verification if the candidate's bounding box covers less than 15% of the frame.
      // `lastBoundingBox` is already normalised to [0,1] coordinates so width*height gives
      // the fraction of image area occupied.
      let bboxArea = cand.lastBoundingBox.width * cand.lastBoundingBox.height
      let minAreaThreshold: CGFloat = 0.01  // 1% of the image
      if bboxArea < minAreaThreshold {
        print("[Verifier] Candidate \(cand.id) skipped – bbox too small (\(bboxArea * 100)%)")
        continue
      }

      // Skip verification if bounding box is significantly taller than it is wide.
      // Allow roughly square boxes (front/rear views) but reject tall portrait shapes.
      let aspectRatio = cand.lastBoundingBox.height / max(cand.lastBoundingBox.width, 0.0001)
      let maxTallness: CGFloat = 3  // height cannot exceed 300% of width
      if aspectRatio > maxTallness {
        print("[Verifier] Candidate \(cand.id) skipped – bbox too tall (h/w=\(aspectRatio))")
        continue
      }

      if cand.view != .side
        && now.timeIntervalSince(cand.lastMMRTime) < verificationConfig.perCandidateMMRInterval
      {
        // Skip TrafficEye re-verify until per-candidate interval passes.
        print("[Verifier] Candidate \(cand.id) skipped – MMR throttled")
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
      }

      let verifyStartTime = Date()
      // Use strategy manager to handle verification with proper counter management
      strategyManager.verify(image: img, candidate: cand, store: store)
        .sink { completion in
          switch completion {
          case .finished:
            break
          case .failure(let error):
            print("[Verifier] Error for candidate \(cand.id): \(error)")
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
          
          print(
            "[Verifier] Result for candidate \(cand.id): strategy=\(strategyName) match=\(outcome.isMatch) view=\(String(describing: outcome.vehicleView)) score=\(String(describing: outcome.viewScore)) reason=\(String(describing: outcome.rejectReason?.rawValue)) latency=\(String(format: "%.3f", latency))s"
          )
          
          // Update view and timing information
          store.update(id: cand.id) { c in
            if let v = outcome.vehicleView, let score = outcome.viewScore {
              c.updateView(v, score: score)
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
            store.update(id: cand.id) {
              $0.detectedDescription = outcome.description
              $0.lastVerified = Date()
            }
            if !self.verificationConfig.shouldRunOCR || outcome.isPlateMatch {
              store.update(id: cand.id) {
                $0.matchStatus = .full
                $0.lastVerified = Date()
              }
              return
            }
            // Promote to partial and begin OCR verification
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
                // Retryable reason - keep searching so candidate will be retried
                $0.matchStatus = .unknown
              } else if reason != nil {
                // Hard reject reason
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
