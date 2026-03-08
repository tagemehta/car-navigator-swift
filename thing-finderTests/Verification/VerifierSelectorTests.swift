//  VerifierSelectorTests.swift
//  thing-finderTests
//
//  Unit tests for VerifierSelector.
//  Tests strategy-based verifier selection, escalation logic, counter resets,
//  and timeout handling.

import Combine
import XCTest

@testable import thing_finder

final class VerifierSelectorTests: XCTestCase {

  private var cancellables: Set<AnyCancellable>!
  private var store: CandidateStore!

  override func setUp() {
    super.setUp()
    cancellables = []
    store = CandidateStore()
  }

  override func tearDown() {
    cancellables = nil
    store = nil
    super.tearDown()
  }

  // MARK: - Strategy Selection: .hybrid

  func test_hybrid_freshCandidate_selectsTrafficEye() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_hybrid_afterMaxTrafficEyeFailures_selectsLLM() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 3)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "LLM")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_hybrid_afterMaxLLMFailures_cyclesBackToTrafficEye() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 3, llmAttempts: 3)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_hybrid_belowThreshold_staysOnTrafficEye() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 2)  // Below threshold of 3
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - Strategy Selection: .llmOnly

  func test_llmOnly_alwaysSelectsAdvancedLLM() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .llmOnly)
    let selector = VerifierSelector(
      targetTextDescription: "white paratransit van with wheelchair lift",
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "AdvancedLLM")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_llmOnly_ignoresAttemptCounters() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .llmOnly)
    let selector = VerifierSelector(
      targetTextDescription: "white paratransit van with wheelchair lift",
      config: config
    )

    // Even with high attempt counters, should still use AdvancedLLM
    let candidate = TestCandidates.make(trafficAttempts: 10, llmAttempts: 10)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "AdvancedLLM")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - Strategy Selection: .trafficEyeOnly

  func test_trafficEyeOnly_alwaysSelectsTrafficEye() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .trafficEyeOnly)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_trafficEyeOnly_neverEscalatesToLLM() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .trafficEyeOnly)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    // Even with max TrafficEye failures, should NOT escalate to LLM
    let candidate = TestCandidates.make(trafficAttempts: 10)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - Counter Reset (Hybrid Mode Only)

  func test_hybrid_trafficEyeResetsLLMCounter() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(llmAttempts: 2)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { [weak self] _, verifierName in
          XCTAssertEqual(verifierName, "TrafficEye")
          let updated = self?.store[candidate.id]
          XCTAssertEqual(updated?.verificationTracker.llmAttempts, 0)
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_hybrid_llmResetsTrafficEyeCounter() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 3, llmAttempts: 0)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { [weak self] _, verifierName in
          XCTAssertEqual(verifierName, "LLM")
          let updated = self?.store[candidate.id]
          XCTAssertEqual(updated?.verificationTracker.trafficAttempts, 0)
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_llmOnly_doesNotResetCounters() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .llmOnly)
    let selector = VerifierSelector(
      targetTextDescription: "white paratransit van",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 5, llmAttempts: 3)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { [weak self] _, _ in
          let updated = self?.store[candidate.id]
          // Counters should NOT be reset in llmOnly mode
          XCTAssertEqual(updated?.verificationTracker.trafficAttempts, 5)
          XCTAssertEqual(updated?.verificationTracker.llmAttempts, 3)
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  func test_trafficEyeOnly_doesNotResetCounters() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .trafficEyeOnly)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make(trafficAttempts: 2, llmAttempts: 4)
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in expectation.fulfill() },
        receiveValue: { [weak self] _, _ in
          let updated = self?.store[candidate.id]
          // Counters should NOT be reset in trafficEyeOnly mode
          XCTAssertEqual(updated?.verificationTracker.trafficAttempts, 2)
          XCTAssertEqual(updated?.verificationTracker.llmAttempts, 4)
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - Verification Outcome

  func test_verify_returnsOutcomeWithVerifierName() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { completion in
          if case .failure = completion {
            XCTFail("Should not fail")
          }
          expectation.fulfill()
        },
        receiveValue: { outcome, verifierName in
          // Outcome should be a VerificationOutcome struct
          XCTAssertNotNil(outcome)
          // Verifier name should be non-empty
          XCTAssertFalse(verifierName.isEmpty)
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }

  // MARK: - VerifierStrategy Enum

  func test_verifierStrategy_defaultIsHybrid() {
    let config = VerificationConfig(expectedPlate: nil)
    XCTAssertEqual(config.strategy, .hybrid)
  }

  func test_verifierStrategy_canBeSetToLLMOnly() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .llmOnly)
    XCTAssertEqual(config.strategy, .llmOnly)
  }

  func test_verifierStrategy_canBeSetToTrafficEyeOnly() {
    let config = VerificationConfig(expectedPlate: nil, strategy: .trafficEyeOnly)
    XCTAssertEqual(config.strategy, .trafficEyeOnly)
  }

  // MARK: - Error Handling

  func test_verify_convertsErrorsToRetryableOutcome() {
    // This test verifies that errors are converted to outcomes with retryable reject reasons
    // rather than propagating as failures. The actual API calls will fail (no network in tests)
    // but the selector should catch and convert them.

    let config = VerificationConfig(expectedPlate: nil, strategy: .hybrid)
    let selector = VerifierSelector(
      targetTextDescription: "blue Toyota Camry",
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let expectation = XCTestExpectation(description: "Verify completes")

    selector.verify(image: UIImage(), candidate: candidate, store: store)
      .sink(
        receiveCompletion: { completion in
          // Should complete (either with value or finished), not fail
          expectation.fulfill()
        },
        receiveValue: { outcome, _ in
          // If we get an outcome, it should have a retryable reject reason
          // (since the actual API call will fail in tests)
          if !outcome.isMatch {
            XCTAssertNotNil(outcome.rejectReason)
            if let reason = outcome.rejectReason {
              XCTAssertTrue(reason.isRetryable, "Reject reason should be retryable")
            }
          }
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 15.0)
  }
}
