//  DetectionStateMachine.swift
//  thing-finder
//
//  Stateless reducer that inspects an immutable snapshot of current
//  `Candidate`s and derives the global `DetectionPhase`.  This version is
//  anchor-free and works in both AVFoundation & ARKit capture modes.
//
//  Pure Swift – no ARKit, Vision or UIKit dependencies so it can be trivially
//  unit-tested in CI (macOS target).

import Foundation

/// Simple value-type state machine.  Hold as a `var` inside the coordinator and
/// call `update(snapshot:)` once per frame.
public struct DetectionStateMachine {
  /// Current phase (public read-only)
  public private(set) var phase: DetectionPhase = .searching

  /// Update the phase from the latest candidate snapshot.
  /// – The snapshot should be a stable view of the `CandidateStore` for this frame.
  /// – Complexity O(n) over candidate count (usually small).
  public mutating func update(snapshot: [Candidate]) {
    // Fast path: no candidates
    guard !snapshot.isEmpty else {
      phase = .searching
      return
    }

    // Look for first matched candidate (verifier approved)
    if let match = snapshot.first(where: { $0.matchStatus == .full }) {
      phase = .found(candidateID: match.id)
      return
    }

    // Strip lost variants before computing the verifying set.
    // lostVerified/lostPartial are confirmed matches that simply lost tracking — showing
    // "checking…" for them is misleading. lostUnknown has no bbox and its API call is still
    // in-flight, so it also shouldn't surface as a visible verifying candidate.
    let verifying = snapshot.filter {
      $0.matchStatus != .lostVerified
        && $0.matchStatus != .lostPartial
        && $0.matchStatus != .lostUnknown
    }
    guard !verifying.isEmpty else {
      phase = .searching
      return
    }
    phase = .verifying(candidateIDs: verifying.map { $0.id })
  }
}
