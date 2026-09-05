/// VerifierSelector
/// ----------------
/// Selects and executes the appropriate verifier based on `VerificationConfig.strategy`.
///
/// Replaces the previous Strategy → StrategyManager → Factory layering with
/// a single class that owns selection, counter-reset, timeout, and error handling.
///
/// ### Strategies
/// - **hybrid**: TrafficEye → TwoStepVerifier escalation loop (standard car search)
/// - **llmOnly**: Always use AdvancedLLMVerifier (custom features)
/// - **trafficEyeOnly**: Always use TrafficEye, never escalate (simple MMR-only)
/// - **paratransit**: TrafficEye → AdvancedLLMVerifier escalation loop (buses/transit)
///
/// ### Escalation loop (hybrid and paratransit modes)
/// TrafficEye is tried first. After `maxTrafficEyeRetries` consecutive
/// failures the selector switches to LLM and resets the TrafficEye counter.
/// After `maxLLMRetries` LLM failures it cycles back.
/// - hybrid uses TwoStepVerifier for LLM step
/// - paratransit uses AdvancedLLMVerifier (prompted for route numbers, logos)

import Combine
import Foundation
import SwiftUI

// MARK: - Errors

public enum VerificationError: Error, LocalizedError, Equatable {
  case timeout

  public var errorDescription: String? {
    switch self {
    case .timeout:
      return "Verification timed out"
    }
  }
}

// MARK: - Internal Types

private enum VerifierKind {
  case trafficEye
  case llm
}

// MARK: - Selector

public final class VerifierSelector {

  // MARK: - Verifiers (instantiated based on strategy)

  private let trafficEye: TrafficEyeVerifier?
  private let llmVerifier: TwoStepVerifier?
  private let advancedLLM: AdvancedLLMVerifier?

  // MARK: - Config

  let targetTextDescription: String
  private let config: VerificationConfig
  private let strategy: VerifierStrategy
  private let apiHealthMonitor: APIHealthMonitorProtocol

  /// Timeout applied to each individual verification call.
  /// TrafficEye is hybrid (API + OpenAI) so allow enough headroom.
  private let perCallTimeout: TimeInterval = 10

  // MARK: - Escalation thresholds (hybrid mode)

  /// TrafficEye failures before escalating to LLM
  private static let maxTrafficEyeRetries: Int = 3
  /// LLM failures before cycling back to TrafficEye
  private static let maxLLMRetries: Int = 3

  // MARK: - Escalation thresholds (paratransit mode)

  /// TrafficEye failures before escalating to LLM (paratransit)
  private static let maxTrafficEyeRetriesParatransit: Int = 1
  /// LLM failures before cycling back to TrafficEye (paratransit)
  private static let maxLLMRetriesParatransit: Int = 3

  // MARK: - Init

  public init(
    targetTextDescription: String,
    config: VerificationConfig,
    apiHealthMonitor: APIHealthMonitorProtocol = APIHealthMonitor.shared
  ) {
    self.targetTextDescription = targetTextDescription
    self.config = config
    self.strategy = config.strategy
    self.apiHealthMonitor = apiHealthMonitor

    // Only instantiate verifiers we'll actually use
    switch config.strategy {
    case .hybrid:
      self.trafficEye = TrafficEyeVerifier(
        targetTextDescription: targetTextDescription,
        config: config
      )
      self.llmVerifier = TwoStepVerifier(
        targetTextDescription: targetTextDescription
      )
      self.advancedLLM = nil

    case .llmOnly:
      self.trafficEye = nil
      self.llmVerifier = nil
      self.advancedLLM = AdvancedLLMVerifier(
        targetTextDescription: targetTextDescription
      )

    case .trafficEyeOnly:
      self.trafficEye = TrafficEyeVerifier(
        targetTextDescription: targetTextDescription,
        config: config
      )
      self.llmVerifier = nil
      self.advancedLLM = nil

    case .paratransit:
      self.trafficEye = TrafficEyeVerifier(
        targetTextDescription: targetTextDescription,
        config: config
      )
      self.llmVerifier = nil
      self.advancedLLM = AdvancedLLMVerifier(
        targetTextDescription: targetTextDescription,
      )
    }
  }

  // MARK: - Public API

  /// Select the appropriate verifier, reset the opposite counter (hybrid mode),
  /// execute, and return the outcome together with the verifier name used.
  public func verify(
    image: UIImage,
    candidate: Candidate,
    store: CandidateStore
  ) -> AnyPublisher<(VerificationOutcome, String), Error> {

    let kind = selectVerifier(for: candidate)
    let verifierName: String

    // Reset opposite counter when switching engines (hybrid and paratransit modes)
    if strategy == .hybrid || strategy == .paratransit {
      switch kind {
      case .trafficEye:
        verifierName = "TrafficEye"
        store.update(id: candidate.id) { $0.verificationTracker.llmAttempts = 0 }
      case .llm:
        verifierName = strategy == .paratransit ? "AdvancedLLM" : "LLM"
        store.update(id: candidate.id) { $0.verificationTracker.trafficAttempts = 0 }
      }
    } else {
      verifierName = strategy == .llmOnly ? "AdvancedLLM" : "TrafficEye"
    }

    DebugPublisher.shared.info(
      "[VerifierSelector][\(candidate.id.uuidString.suffix(8))] Selected: \(verifierName) (strategy: \(strategy))"
    )

    let publisher: AnyPublisher<VerificationOutcome, Error>
    switch (kind, strategy) {
    case (.trafficEye, _):
      guard let te = trafficEye else {
        fatalError("TrafficEye not available for strategy \(strategy)")
      }
      publisher = te.verify(image: image, candidateId: candidate.id)

    case (.llm, .hybrid):
      guard let llm = llmVerifier else {
        fatalError("TwoStepVerifier not available for strategy \(strategy)")
      }
      publisher = llm.verify(image: image, candidateId: candidate.id)

    case (.llm, .llmOnly), (.llm, .paratransit):
      guard let adv = advancedLLM else {
        fatalError("AdvancedLLMVerifier not available for strategy \(strategy)")
      }
      publisher = adv.verify(image: image, candidateId: candidate.id)

    case (.llm, .trafficEyeOnly):
      fatalError("LLM selected but strategy is trafficEyeOnly")
    }

    return
      publisher
      .timeout(
        .seconds(Int(perCallTimeout)),
        scheduler: DispatchQueue.main,
        customError: { VerificationError.timeout }
      )
      .catch { error -> AnyPublisher<VerificationOutcome, Error> in
        Self.outcomeForError(error)
      }
      .map { outcome -> (VerificationOutcome, String) in
        // Inspect the final outcome rather than the raw publisher event: some
        // verifiers (e.g. TrafficEyeVerifier) catch their own network errors
        // internally and surface them as a non-throwing `.networkError`
        // outcome, so a request can "succeed" at the Combine level while
        // still representing a connectivity failure.
        //
        // Some outcomes (e.g. a blurry image rejected before any API call,
        // or a local JPEG-encode failure) never touch the network at all.
        // Those must not be mistaken for a successful request, so they're
        // excluded via `didCompleteNetworkRequest` rather than reporting a
        // spurious success.
        if outcome.rejectReason == .networkError {
          self.apiHealthMonitor.recordFailure(isConnectivityRelated: true)
        } else if outcome.didCompleteNetworkRequest {
          self.apiHealthMonitor.recordSuccess()
        }
        return (outcome, verifierName)
      }
      .eraseToAnyPublisher()
  }

  // MARK: - Helpers

  /// Select which verifier to use based on strategy and attempt counters.
  private func selectVerifier(for candidate: Candidate) -> VerifierKind {
    switch strategy {
    case .hybrid:
      // Escalation logic: TrafficEye → LLM → TrafficEye...
      if candidate.verificationTracker.llmAttempts >= Self.maxLLMRetries {
        return .trafficEye
      }
      if candidate.verificationTracker.trafficAttempts >= Self.maxTrafficEyeRetries {
        return .llm
      }
      return .trafficEye

    case .llmOnly:
      return .llm

    case .trafficEyeOnly:
      return .trafficEye

    case .paratransit:
      // Always use AdvancedLLM for transit mode
      // To restore escalation loop: use hybrid-style logic with maxTrafficEyeRetriesParatransit/maxLLMRetriesParatransit
      return .llm
    }
  }

  /// Convert a verification error into a non-fatal rejection outcome so the
  /// escalation loop can continue.
  private static func outcomeForError(
    _ error: Error
  ) -> AnyPublisher<VerificationOutcome, Error> {
    let reason: RejectReason
    if let verificationError = error as? VerificationError,
      verificationError == .timeout
    {
      DebugPublisher.shared.warning("[VerifierSelector] Verification timed out")
      reason = .networkError  // retryable, and a signal for APIHealthMonitor
    } else if let twoStep = error as? TwoStepError {
      switch twoStep {
      case .noToolResponse: reason = .apiError
      case .networkError: reason = .networkError
      case .occluded: reason = .unclearImage
      case .lowConfidence: reason = .lowConfidence
      }
    } else {
      reason = NetworkErrorClassifier.isConnectivityError(error) ? .networkError : .apiError
    }
    // The request threw — timed out, failed in transport, or returned
    // something we couldn't decode. None of that is evidence the API is
    // healthy, so it must not clear an existing degradation.
    let outcome = VerificationOutcome(
      isMatch: false, description: "", rejectReason: reason,
      didCompleteNetworkRequest: false
    )
    return Just(outcome)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }
}
