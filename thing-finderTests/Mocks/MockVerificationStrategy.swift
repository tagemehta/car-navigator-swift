//  MockVerificationStrategy.swift
//  thing-finderTests
//
//  Mock implementation of VerificationStrategy for testing VerificationStrategyManager.

import Combine
import Foundation
import UIKit

@testable import thing_finder

/// Mock verification strategy for testing strategy selection and execution.
final class MockVerificationStrategy: VerificationStrategy {

  let strategyName: String
  private let _shouldUse: (Candidate) -> Bool
  private let _priority: (Candidate) -> Int
  private let _outcome: VerificationOutcome?
  private let _error: Error?

  /// Tracks how many times verify was called.
  private(set) var verifyCallCount: Int = 0

  /// Records candidates passed to verify.
  private(set) var verifiedCandidates: [Candidate] = []

  init(
    name: String,
    shouldUse: @escaping (Candidate) -> Bool = { _ in true },
    priority: @escaping (Candidate) -> Int = { _ in 50 },
    outcome: VerificationOutcome? = nil,
    error: Error? = nil
  ) {
    self.strategyName = name
    self._shouldUse = shouldUse
    self._priority = priority
    self._outcome = outcome
    self._error = error
  }

  func verify(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
    verifyCallCount += 1
    verifiedCandidates.append(candidate)

    if let error = _error {
      return Fail(error: error).eraseToAnyPublisher()
    }

    let outcome =
      _outcome
      ?? VerificationOutcome(
        isMatch: false,
        description: "mock",
        rejectReason: .apiError
      )
    return Just(outcome)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }

  func shouldUse(for candidate: Candidate) -> Bool {
    return _shouldUse(candidate)
  }

  func priority(for candidate: Candidate) -> Int {
    return _priority(candidate)
  }

  /// Resets call tracking state.
  func reset() {
    verifyCallCount = 0
    verifiedCandidates = []
  }
}

// MARK: - Convenience Factories

extension MockVerificationStrategy {

  /// Creates a strategy that always matches.
  static func alwaysMatch(name: String = "AlwaysMatch", priority: Int = 50)
    -> MockVerificationStrategy
  {
    return MockVerificationStrategy(
      name: name,
      priority: { _ in priority },
      outcome: VerificationOutcome(isMatch: true, description: "matched", rejectReason: .success)
    )
  }

  /// Creates a strategy that always rejects.
  static func alwaysReject(
    name: String = "AlwaysReject", priority: Int = 50, reason: RejectReason = .wrongModelOrColor
  ) -> MockVerificationStrategy {
    return MockVerificationStrategy(
      name: name,
      priority: { _ in priority },
      outcome: VerificationOutcome(isMatch: false, description: "rejected", rejectReason: reason)
    )
  }

  /// Creates a strategy that always fails with an error.
  static func alwaysFail(
    name: String = "AlwaysFail", priority: Int = 50, error: Error = VerificationError.timeout
  ) -> MockVerificationStrategy {
    return MockVerificationStrategy(
      name: name,
      priority: { _ in priority },
      error: error
    )
  }

  /// Creates a TrafficEye-like strategy.
  /// Matches VerificationPolicy.nextKind logic: TrafficEye is used when LLM has exceeded retries
  /// OR when TrafficEye hasn't exceeded its retries yet.
  static func trafficEye(priority: Int = 80, outcome: VerificationOutcome? = nil)
    -> MockVerificationStrategy
  {
    return MockVerificationStrategy(
      name: "TrafficEye",
      shouldUse: { candidate in
        // TrafficEye is suitable when:
        // 1. LLM has failed too many times (cycle back), OR
        // 2. TrafficEye hasn't exceeded its retries yet
        candidate.verificationTracker.llmAttempts >= VerificationPolicy.maxLLMRetries
          || candidate.verificationTracker.trafficAttempts < VerificationPolicy.maxPrimaryRetries
      },
      priority: { candidate in
        var p = priority
        // Boost priority when cycling back from LLM failures
        if candidate.verificationTracker.llmAttempts >= VerificationPolicy.maxLLMRetries {
          p += 30
        }
        p -= candidate.verificationTracker.trafficAttempts * 10
        return max(0, p)
      },
      outcome: outcome
    )
  }

  /// Creates an LLM-like strategy.
  /// Matches VerificationPolicy.nextKind logic: LLM is used when TrafficEye has exceeded retries
  /// AND LLM hasn't exceeded its retries yet.
  static func llm(priority: Int = 60, outcome: VerificationOutcome? = nil)
    -> MockVerificationStrategy
  {
    return MockVerificationStrategy(
      name: "LLM",
      shouldUse: { candidate in
        // LLM is suitable when TrafficEye has failed AND LLM hasn't exceeded retries
        candidate.verificationTracker.trafficAttempts >= VerificationPolicy.maxPrimaryRetries
          && candidate.verificationTracker.llmAttempts < VerificationPolicy.maxLLMRetries
      },
      priority: { candidate in
        var p = priority
        if candidate.verificationTracker.trafficAttempts >= VerificationPolicy.maxPrimaryRetries {
          p += 30  // Prefer LLM if TE has failed multiple times
        }
        if candidate.view == .side {
          p += 10  // LLM is better for side views
        }
        p -= candidate.verificationTracker.llmAttempts * 10
        return max(0, p)
      },
      outcome: outcome
    )
  }
}
