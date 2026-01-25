//  TestCandidates.swift
//  thing-finderTests
//
//  Factory helpers for creating Candidate instances in tests.
//  Uses TrackingRequest struct directly (no Vision dependency needed).

import CoreGraphics
import Foundation

@testable import thing_finder

enum TestCandidates {
  /// Creates a basic candidate with default values for testing.
  static func make(
    id: CandidateID = UUID(),
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
    matchStatus: MatchStatus = .unknown,
    missCount: Int = 0,
    view: Candidate.VehicleView = .unknown,
    viewScore: Double = 0.0,
    trafficAttempts: Int = 0,
    llmAttempts: Int = 0,
    embedding: Embedding? = nil
  ) -> Candidate {
    let request = TrackingRequest(boundingBox: boundingBox)
    var candidate = Candidate(
      id: id,
      trackingRequest: request,
      boundingBox: boundingBox,
      embedding: embedding
    )
    candidate.matchStatus = matchStatus
    candidate.missCount = missCount
    candidate.view = view
    candidate.viewScore = viewScore
    candidate.verificationTracker.trafficAttempts = trafficAttempts
    candidate.verificationTracker.llmAttempts = llmAttempts
    return candidate
  }

  /// Creates a matched (full) candidate.
  static func makeMatched(
    id: CandidateID = UUID(),
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  ) -> Candidate {
    make(id: id, boundingBox: boundingBox, matchStatus: .full)
  }

  /// Creates a candidate in waiting state.
  static func makeWaiting(
    id: CandidateID = UUID(),
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  ) -> Candidate {
    make(id: id, boundingBox: boundingBox, matchStatus: .waiting)
  }

  /// Creates a rejected candidate.
  static func makeRejected(
    id: CandidateID = UUID(),
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
    reason: RejectReason = .wrongModelOrColor
  ) -> Candidate {
    var candidate = make(id: id, boundingBox: boundingBox, matchStatus: .rejected)
    candidate.rejectReason = reason
    return candidate
  }

  /// Creates a lost candidate (was matched but tracking failed).
  static func makeLost(
    id: CandidateID = UUID(),
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  ) -> Candidate {
    make(id: id, boundingBox: boundingBox, matchStatus: .lost)
  }
}
