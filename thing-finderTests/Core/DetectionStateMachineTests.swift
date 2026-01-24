//  DetectionStateMachineTests.swift
//  thing-finderTests
//
//  Unit tests for DetectionStateMachine state reducer.

import XCTest

@testable import thing_finder

final class DetectionStateMachineTests: XCTestCase {

  var stateMachine: DetectionStateMachine!

  override func setUp() {
    super.setUp()
    stateMachine = DetectionStateMachine()
  }

  override func tearDown() {
    stateMachine = nil
    super.tearDown()
  }

  // MARK: - Initial State

  func test_initialState_isSearching() {
    XCTAssertEqual(stateMachine.phase, .searching)
  }

  // MARK: - Empty Store

  func test_emptyStore_returnsSearching() {
    stateMachine.update(snapshot: [])

    XCTAssertEqual(stateMachine.phase, .searching)
  }

  // MARK: - Unknown Candidates

  func test_unknownCandidates_returnsVerifying() {
    let candidates = [
      TestCandidates.make(matchStatus: .unknown),
      TestCandidates.make(matchStatus: .unknown),
    ]

    stateMachine.update(snapshot: candidates)

    if case .verifying(let ids) = stateMachine.phase {
      XCTAssertEqual(ids.count, 2)
    } else {
      XCTFail("Expected .verifying phase")
    }
  }

  // MARK: - Waiting Candidates

  func test_waitingCandidates_returnsVerifying() {
    let candidates = [
      TestCandidates.make(matchStatus: .waiting),
      TestCandidates.make(matchStatus: .unknown),
    ]

    stateMachine.update(snapshot: candidates)

    if case .verifying(let ids) = stateMachine.phase {
      XCTAssertEqual(ids.count, 2)
    } else {
      XCTFail("Expected .verifying phase")
    }
  }

  // MARK: - Full (Matched) Candidate

  func test_fullCandidate_returnsFound() {
    let matchedId = UUID()
    let candidates = [
      TestCandidates.make(matchStatus: .unknown),
      TestCandidates.make(id: matchedId, matchStatus: .full),
    ]

    stateMachine.update(snapshot: candidates)

    if case .found(let id) = stateMachine.phase {
      XCTAssertEqual(id, matchedId)
    } else {
      XCTFail("Expected .found phase")
    }
  }

  // MARK: - Priority Order

  func test_priorityOrder_foundBeatsVerifying() {
    let matchedId = UUID()
    let candidates = [
      TestCandidates.make(matchStatus: .waiting),
      TestCandidates.make(matchStatus: .unknown),
      TestCandidates.make(id: matchedId, matchStatus: .full),
      TestCandidates.make(matchStatus: .partial),
    ]

    stateMachine.update(snapshot: candidates)

    if case .found(let id) = stateMachine.phase {
      XCTAssertEqual(id, matchedId)
    } else {
      XCTFail("Expected .found phase, got \(stateMachine.phase)")
    }
  }

  func test_priorityOrder_firstFullWins() {
    let firstMatchedId = UUID()
    let secondMatchedId = UUID()
    let candidates = [
      TestCandidates.make(id: firstMatchedId, matchStatus: .full),
      TestCandidates.make(id: secondMatchedId, matchStatus: .full),
    ]

    stateMachine.update(snapshot: candidates)

    if case .found(let id) = stateMachine.phase {
      XCTAssertEqual(id, firstMatchedId)
    } else {
      XCTFail("Expected .found phase")
    }
  }

  // MARK: - Rejected/Lost Candidates

  func test_rejectedCandidates_returnsVerifying() {
    let candidates = [
      TestCandidates.make(matchStatus: .rejected),
      TestCandidates.make(matchStatus: .unknown),
    ]

    stateMachine.update(snapshot: candidates)

    if case .verifying(let ids) = stateMachine.phase {
      XCTAssertEqual(ids.count, 2)
    } else {
      XCTFail("Expected .verifying phase")
    }
  }

  func test_lostCandidates_returnsVerifying() {
    let candidates = [
      TestCandidates.make(matchStatus: .lost)
    ]

    stateMachine.update(snapshot: candidates)

    if case .verifying(let ids) = stateMachine.phase {
      XCTAssertEqual(ids.count, 1)
    } else {
      XCTFail("Expected .verifying phase")
    }
  }

  // MARK: - State Transitions

  func test_stateTransition_searchingToVerifying() {
    XCTAssertEqual(stateMachine.phase, .searching)

    stateMachine.update(snapshot: [TestCandidates.make()])

    if case .verifying = stateMachine.phase {
      // Success
    } else {
      XCTFail("Expected transition to .verifying")
    }
  }

  func test_stateTransition_verifyingToFound() {
    stateMachine.update(snapshot: [TestCandidates.make(matchStatus: .unknown)])
    guard case .verifying = stateMachine.phase else {
      XCTFail("Expected .verifying phase")
      return
    }

    let matchedId = UUID()
    stateMachine.update(snapshot: [TestCandidates.make(id: matchedId, matchStatus: .full)])

    if case .found(let id) = stateMachine.phase {
      XCTAssertEqual(id, matchedId)
    } else {
      XCTFail("Expected transition to .found")
    }
  }

  func test_stateTransition_foundToSearching() {
    let matchedId = UUID()
    stateMachine.update(snapshot: [TestCandidates.make(id: matchedId, matchStatus: .full)])
    guard case .found = stateMachine.phase else {
      XCTFail("Expected .found phase")
      return
    }

    stateMachine.update(snapshot: [])

    XCTAssertEqual(stateMachine.phase, .searching)
  }
}
