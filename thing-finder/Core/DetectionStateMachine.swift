//  DetectionStateMachine.swift
//  Stateless phase engine that inspects an immutable snapshot of current
//  candidates and determines the global detection phase. Pure Swift – no
//  ARKit, Vision or UIKit dependencies so it can be trivially unit-tested.

import Foundation

/// Global phase of the object-detection pipeline.
enum DetectionPhase: Equatable {
  case searching  // No active candidates
  case verifying(candidateIDs: [CandidateID])  // Tracking candidates, waiting on LLM and/or anchor
  case found(anchorId: UUID, candidateId: CandidateID)  // Confirmed match with AR anchor
}

/// Simple value-type state machine. Hold as a `var` inside a coordinator and
/// call `update(snapshot:)` once per frame.
struct DetectionStateMachine {
  /// Current phase (public read-only)
  public private(set) var phase: DetectionPhase = .searching

  /// Update the phase from the latest candidate snapshot.
  /// – The snapshot should be a stable view of the CandidateStore for this frame.
  /// – Complexity O(n) over candidate count (usually small).
  public mutating func update(snapshot: [Candidate]) {
    // 0. Fast path: no candidates
    guard !snapshot.isEmpty else {
      phase = .searching
      return
    }

    // 1. Look for first candidate that has both a match and an anchor
    if let winner = snapshot.first(where: { $0.matchStatus == .matched && $0.anchorId != nil }) {
      phase = .found(anchorId: winner.anchorId!, candidateId: winner.id)
      return
    }

    // 2. Otherwise we are verifying – collect ids for convenience
    let ids = snapshot.map { $0.id }
    phase = .verifying(candidateIDs: ids)
  }
}
