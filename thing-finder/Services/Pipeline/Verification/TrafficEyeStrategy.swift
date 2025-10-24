//  TrafficEyeStrategy.swift
//  thing-finder
//
//  TrafficEye verification strategy implementation that wraps the existing
//  TrafficEyeVerifier with the new strategy interface.
//
//  Created by Cascade AI.

import Combine
import Foundation
import SwiftUI

/// TrafficEye verification strategy implementation.
///
/// This strategy wraps the existing TrafficEyeVerifier with the new strategy interface.
/// It serves as the primary, fast verification method and is prioritized for front-view
/// candidates and initial verification attempts.
///
/// ## Topics
///
/// ### Creating a TrafficEye Strategy
/// - ``init(targetTextDescription:config:)``
///
/// ### Strategy Selection Logic
/// - ``shouldUse(for:)``
/// - ``priority(for:)``
public class TrafficEyeStrategy: BaseVerificationStrategy {

  /// The underlying TrafficEye verifier instance.
  private let trafficEyeVerifier: TrafficEyeVerifier

  /// Initializes a new TrafficEye verification strategy.
  ///
  /// - Parameters:
  ///   - targetTextDescription: The target text description to verify against
  ///   - config: Configuration for the verification process
  public init(targetTextDescription: String, config: VerificationConfig) {
    self.trafficEyeVerifier = TrafficEyeVerifier(
      targetTextDescription: targetTextDescription,
      config: config
    )

    super.init(
      strategyName: "TrafficEye",
      targetTextDescription: targetTextDescription,
      config: config
    )
  }

  // MARK: - Strategy Selection Logic

  /// Check if this strategy should be used for the given candidate.
  ///
  /// This method replicates the exact logic from the original `VerificationPolicy.nextKind()`
  /// method for TrafficEye selection, ensuring backward compatibility with the
  /// original verification system.
  ///
  /// - Parameter candidate: The candidate to evaluate
  /// - Returns: True if TrafficEye is appropriate for the candidate
  public override func shouldUse(for candidate: Candidate) -> Bool {
    // Replicate exact VerificationPolicy.nextKind() logic for TrafficEye

    // First: if LLM has already failed too many times, cycle back to TrafficEye
    if candidate.verificationTracker.llmAttempts >= VerificationPolicy.maxLLMRetries {
      return meetsBasicRequirements(candidate)
    }

    // Don't use TrafficEye if it should escalate to LLM (any view)
    if candidate.verificationTracker.trafficAttempts >= VerificationPolicy.maxPrimaryRetries {
      return false
    }

    // --COMMENTED OUT 10/23 due to changes in side view ability of traffic eye--
    // Don't use TrafficEye for side view after minPrimaryRetries failures
    // if candidate.view == .side
    //   && candidate.verificationTracker.trafficAttempts >= VerificationPolicy.minPrimaryRetries
    // {
    //   return false
    // }

    // Default to TrafficEye (matches original policy)
    return meetsBasicRequirements(candidate)
  }

  /// Get the priority of this strategy (higher = more preferred).
  ///
  /// TrafficEye gets the highest priority (100) when it should be used,
  /// ensuring it is selected as the default verification method when appropriate.
  ///
  /// - Parameter candidate: The candidate to evaluate
  /// - Returns: Priority score (0 or 100)
  public override func priority(for candidate: Candidate) -> Int {
    // TrafficEye gets highest priority when it should be used (matches original policy default)
    return meetsBasicRequirements(candidate) ? 100 : 0
  }

  // MARK: - Verification Implementation

  /// Perform the actual verification using TrafficEye.
  ///
  /// This method delegates the verification to the underlying TrafficEyeVerifier instance.
  ///
  /// - Parameters:
  ///   - image: The image to verify
  ///   - candidate: The candidate being verified
  /// - Returns: Publisher that emits verification outcome
  internal override func performVerification(
    image: UIImage,
    candidate: Candidate
  ) -> AnyPublisher<VerificationOutcome, Error> {
    return trafficEyeVerifier.verify(image: image, candidateId: candidate.id)
  }
}
