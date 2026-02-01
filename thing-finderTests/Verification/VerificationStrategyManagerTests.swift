//  VerificationStrategyManagerTests.swift
//  thing-finderTests
//
//  Unit tests for VerificationStrategyManager.
//  Tests strategy selection, priority ordering, and counter management.

import Combine
import XCTest

@testable import thing_finder

final class VerificationStrategyManagerTests: XCTestCase {

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

  // MARK: - Strategy Selection

  func test_selectStrategy_choosesHighestPriority() {
    let lowPriority = MockVerificationStrategy(
      name: "LowPriority",
      priority: { _ in 30 }
    )
    let highPriority = MockVerificationStrategy(
      name: "HighPriority",
      priority: { _ in 80 }
    )
    let mediumPriority = MockVerificationStrategy(
      name: "MediumPriority",
      priority: { _ in 50 }
    )

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [lowPriority, highPriority, mediumPriority],
      config: config
    )

    let candidate = TestCandidates.make()
    let selected = manager.selectStrategy(for: candidate)

    XCTAssertEqual(selected?.strategyName, "HighPriority")
  }

  func test_selectStrategy_filtersUnsuitableStrategies() {
    let unsuitable = MockVerificationStrategy(
      name: "Unsuitable",
      shouldUse: { _ in false },
      priority: { _ in 100 }  // Highest priority but unsuitable
    )
    let suitable = MockVerificationStrategy(
      name: "Suitable",
      shouldUse: { _ in true },
      priority: { _ in 50 }
    )

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [unsuitable, suitable],
      config: config
    )

    let candidate = TestCandidates.make()
    let selected = manager.selectStrategy(for: candidate)

    XCTAssertEqual(selected?.strategyName, "Suitable")
  }

  func test_selectStrategy_returnsNilWhenAllUnsuitable() {
    let unsuitable1 = MockVerificationStrategy(
      name: "Unsuitable1",
      shouldUse: { _ in false }
    )
    let unsuitable2 = MockVerificationStrategy(
      name: "Unsuitable2",
      shouldUse: { _ in false }
    )

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [unsuitable1, unsuitable2],
      config: config
    )

    let candidate = TestCandidates.make()
    let selected = manager.selectStrategy(for: candidate)

    XCTAssertNil(selected)
  }

  func test_selectStrategy_emptyStrategies_returnsNil() {
    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [],
      config: config
    )

    let candidate = TestCandidates.make()
    let selected = manager.selectStrategy(for: candidate)

    XCTAssertNil(selected)
  }

  // MARK: - Priority Based on Candidate State

  func test_selectStrategy_priorityChangesBasedOnAttempts() {
    // TrafficEye starts with higher priority
    let trafficEye = MockVerificationStrategy.trafficEye()
    let llm = MockVerificationStrategy.llm()

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [trafficEye, llm],
      config: config
    )

    // Fresh candidate - TrafficEye should be selected
    var candidate = TestCandidates.make()
    var selected = manager.selectStrategy(for: candidate)
    XCTAssertEqual(selected?.strategyName, "TrafficEye")

    // After TrafficEye failures, LLM should be preferred
    candidate.verificationTracker.trafficAttempts = 3
    store.upsert(candidate)
    selected = manager.selectStrategy(for: candidate)
    XCTAssertEqual(selected?.strategyName, "LLM")
  }

  func test_selectStrategy_cyclesBackToTrafficEyeAfterLLMFailures() {
    let trafficEye = MockVerificationStrategy.trafficEye()
    let llm = MockVerificationStrategy.llm()

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [trafficEye, llm],
      config: config
    )

    // Candidate with both strategies having failed
    var candidate = TestCandidates.make()
    candidate.verificationTracker.trafficAttempts = 3
    candidate.verificationTracker.llmAttempts = 3

    // Should cycle back to TrafficEye (LLM becomes unsuitable)
    let selected = manager.selectStrategy(for: candidate)
    XCTAssertEqual(selected?.strategyName, "TrafficEye")
  }

  // MARK: - Verify Method

  func test_verify_callsSelectedStrategy() {
    let expectation = XCTestExpectation(description: "Verify completes")

    let strategy = MockVerificationStrategy.alwaysMatch(name: "TestStrategy")
    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [strategy],
      config: config
    )

    let candidate = TestCandidates.make()
    store.upsert(candidate)
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome, strategyName in
          XCTAssertTrue(outcome.isMatch)
          XCTAssertEqual(strategyName, "TestStrategy")
          XCTAssertEqual(strategy.verifyCallCount, 1)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  func test_verify_returnsNoSuitableStrategyError() {
    let expectation = XCTestExpectation(description: "Verify fails")

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [],
      config: config
    )

    let candidate = TestCandidates.make()
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            XCTAssertTrue(error is VerificationError)
            if let verificationError = error as? VerificationError {
              XCTAssertEqual(verificationError, .noSuitableStrategy)
            }
            expectation.fulfill()
          }
        },
        receiveValue: { _, _ in
          XCTFail("Should not receive value")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Counter Reset on Strategy Switch

  func test_verify_resetsLLMCounterWhenSwitchingToTrafficEye() {
    let expectation = XCTestExpectation(description: "Verify completes")

    let trafficEye = MockVerificationStrategy(
      name: "TrafficEye",
      shouldUse: { _ in true },
      priority: { _ in 100 },
      outcome: VerificationOutcome(isMatch: false, description: "", rejectReason: .lowConfidence)
    )

    let config = VerificationConfig(expectedPlate: nil, useCombinedVerifier: true)
    let manager = VerificationStrategyManager(
      strategies: [trafficEye],
      config: config
    )

    var candidate = TestCandidates.make()
    candidate.verificationTracker.llmAttempts = 2  // Has previous LLM failures
    store.upsert(candidate)
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { [weak self] _, _ in
          // LLM counter should be reset when switching to TrafficEye
          let updated = self?.store[candidate.id]
          XCTAssertEqual(updated?.verificationTracker.llmAttempts, 0)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  func test_verify_resetsTrafficEyeCounterWhenSwitchingToLLM() {
    let expectation = XCTestExpectation(description: "Verify completes")

    let llm = MockVerificationStrategy(
      name: "LLM",
      shouldUse: { _ in true },
      priority: { _ in 100 },
      outcome: VerificationOutcome(isMatch: false, description: "", rejectReason: .lowConfidence)
    )

    let config = VerificationConfig(expectedPlate: nil, useCombinedVerifier: true)
    let manager = VerificationStrategyManager(
      strategies: [llm],
      config: config
    )

    var candidate = TestCandidates.make()
    candidate.verificationTracker.trafficAttempts = 2  // Has previous TE failures
    store.upsert(candidate)
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { [weak self] _, _ in
          // TrafficEye counter should be reset when switching to LLM
          let updated = self?.store[candidate.id]
          XCTAssertEqual(updated?.verificationTracker.trafficAttempts, 0)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  func test_verify_doesNotResetCountersWhenCombinedVerifierDisabled() {
    let expectation = XCTestExpectation(description: "Verify completes")

    let trafficEye = MockVerificationStrategy(
      name: "TrafficEye",
      shouldUse: { _ in true },
      priority: { _ in 100 },
      outcome: VerificationOutcome(isMatch: false, description: "", rejectReason: .lowConfidence)
    )

    let config = VerificationConfig(expectedPlate: nil, useCombinedVerifier: false)
    let manager = VerificationStrategyManager(
      strategies: [trafficEye],
      config: config
    )

    var candidate = TestCandidates.make()
    candidate.verificationTracker.llmAttempts = 2
    store.upsert(candidate)
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { [weak self] _, _ in
          // LLM counter should NOT be reset when combined verifier is disabled
          let updated = self?.store[candidate.id]
          XCTAssertEqual(updated?.verificationTracker.llmAttempts, 2)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Strategy Error Handling

  func test_verify_propagatesStrategyError() {
    let expectation = XCTestExpectation(description: "Verify fails")

    let failingStrategy = MockVerificationStrategy.alwaysFail(
      name: "Failing",
      error: VerificationError.timeout
    )

    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [failingStrategy],
      config: config
    )

    let candidate = TestCandidates.make()
    let image = UIImage()

    manager.verify(image: image, candidate: candidate, store: store)
      .sink(
        receiveCompletion: { completion in
          if case .failure = completion {
            expectation.fulfill()
          }
        },
        receiveValue: { _, _ in
          XCTFail("Should not receive value on error")
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }

  // MARK: - Legacy Verify Method

  func test_legacyVerify_worksWithoutStore() {
    let expectation = XCTestExpectation(description: "Verify completes")

    let strategy = MockVerificationStrategy.alwaysMatch()
    let config = VerificationConfig(expectedPlate: nil)
    let manager = VerificationStrategyManager(
      strategies: [strategy],
      config: config
    )

    let candidate = TestCandidates.make()
    let image = UIImage()

    manager.verify(image: image, candidate: candidate)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          XCTAssertTrue(outcome.isMatch)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 1.0)
  }
}
