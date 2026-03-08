//  CandidateTests.swift
//  thing-finderTests
//
//  Unit tests for Candidate value type.

import XCTest

@testable import thing_finder

final class CandidateTests: XCTestCase {

  // MARK: - Initialization Tests

  func test_init_setsDefaultValues() {
    let request = TrackingRequest(boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    let candidate = Candidate(
      trackingRequest: request,
      boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    )

    XCTAssertEqual(candidate.matchStatus, .unknown)
    XCTAssertEqual(candidate.missCount, 0)
    XCTAssertNil(candidate.embedding)
    XCTAssertEqual(candidate.view, .unknown)
    XCTAssertEqual(candidate.viewScore, 0.0)
    XCTAssertEqual(candidate.verificationTracker.trafficAttempts, 0)
    XCTAssertEqual(candidate.verificationTracker.llmAttempts, 0)
    XCTAssertNil(candidate.detectedDescription)
    XCTAssertNil(candidate.rejectReason)
    XCTAssertEqual(candidate.ocrAttempts, 0)
    XCTAssertNil(candidate.ocrText)
  }

  // MARK: - View Assignment Tests

  func test_view_canBeSetDirectly() {
    var candidate = TestCandidates.make(view: .unknown, viewScore: 0.0)

    // View can be set directly (no ranking logic)
    candidate.view = .front
    candidate.viewScore = 0.9
    XCTAssertEqual(candidate.view, .front)
    XCTAssertEqual(candidate.viewScore, 0.9)

    // View can be changed to any value
    candidate.view = .left
    candidate.viewScore = 0.5
    XCTAssertEqual(candidate.view, .left)
    XCTAssertEqual(candidate.viewScore, 0.5)
  }

  func test_vehicleView_isSide() {
    XCTAssertTrue(Candidate.VehicleView.left.isSide)
    XCTAssertTrue(Candidate.VehicleView.right.isSide)
    XCTAssertTrue(Candidate.VehicleView.side.isSide)
    XCTAssertFalse(Candidate.VehicleView.front.isSide)
    XCTAssertFalse(Candidate.VehicleView.rear.isSide)
    XCTAssertFalse(Candidate.VehicleView.unknown.isSide)
  }

  // MARK: - isMatched Tests

  func test_isMatched_returnsTrueOnlyForFull() {
    let fullCandidate = TestCandidates.make(matchStatus: .full)
    XCTAssertTrue(fullCandidate.isMatched)

    let partialCandidate = TestCandidates.make(matchStatus: .partial)
    XCTAssertFalse(partialCandidate.isMatched)

    let unknownCandidate = TestCandidates.make(matchStatus: .unknown)
    XCTAssertFalse(unknownCandidate.isMatched)

    let waitingCandidate = TestCandidates.make(matchStatus: .waiting)
    XCTAssertFalse(waitingCandidate.isMatched)

    let rejectedCandidate = TestCandidates.make(matchStatus: .rejected)
    XCTAssertFalse(rejectedCandidate.isMatched)

    let lostCandidate = TestCandidates.make(matchStatus: .lost)
    XCTAssertFalse(lostCandidate.isMatched)
  }

  // MARK: - VerificationTracker Tests

  func test_verificationTracker_countersIncrementCorrectly() {
    var candidate = TestCandidates.make()

    candidate.verificationTracker.trafficAttempts += 1
    XCTAssertEqual(candidate.verificationTracker.trafficAttempts, 1)
    XCTAssertEqual(candidate.verificationTracker.llmAttempts, 0)

    candidate.verificationTracker.llmAttempts += 1
    XCTAssertEqual(candidate.verificationTracker.trafficAttempts, 1)
    XCTAssertEqual(candidate.verificationTracker.llmAttempts, 1)

    candidate.verificationTracker.trafficAttempts += 2
    candidate.verificationTracker.llmAttempts += 3
    XCTAssertEqual(candidate.verificationTracker.trafficAttempts, 3)
    XCTAssertEqual(candidate.verificationTracker.llmAttempts, 4)
  }

  // MARK: - Equatable Tests

  func test_equatable_sameIdAndRequestAreEqual() {
    let requestId = UUID()
    let request = TrackingRequest(id: requestId, boundingBox: .zero)
    let id = UUID()

    var candidate1 = Candidate(id: id, trackingRequest: request, boundingBox: .zero)
    var candidate2 = Candidate(id: id, trackingRequest: request, boundingBox: .zero)

    XCTAssertEqual(candidate1, candidate2)

    // Changing non-compared fields should still be equal
    candidate1.detectedDescription = "test"
    candidate2.detectedDescription = "different"
    XCTAssertEqual(candidate1, candidate2)
  }

  func test_equatable_differentRequestsAreNotEqual() {
    // Different TrackingRequest IDs means different requests
    let request1 = TrackingRequest(id: UUID(), boundingBox: .zero)
    let request2 = TrackingRequest(id: UUID(), boundingBox: .zero)
    let id = UUID()

    let candidate1 = Candidate(id: id, trackingRequest: request1, boundingBox: .zero)
    let candidate2 = Candidate(id: id, trackingRequest: request2, boundingBox: .zero)

    XCTAssertNotEqual(candidate1, candidate2)
  }

  func test_equatable_differentIdsAreNotEqual() {
    let requestId = UUID()
    let request = TrackingRequest(id: requestId, boundingBox: .zero)

    let candidate1 = Candidate(id: UUID(), trackingRequest: request, boundingBox: .zero)
    let candidate2 = Candidate(id: UUID(), trackingRequest: request, boundingBox: .zero)

    XCTAssertNotEqual(candidate1, candidate2)
  }
}
