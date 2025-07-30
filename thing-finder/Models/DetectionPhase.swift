//  DetectionPhase.swift
//  thing-finder

import Foundation
//  Defines the high-level pipeline state used by the refactored coordinator.
//
//  This enum supersedes and will eventually replace the older `DetectionState`
//  used by `StateController`.  During the migration we’ll keep both types side
//  by side so legacy code continues to compile.

import Foundation

/// Global phase of the object-detection pipeline.
public enum DetectionPhase: Equatable {
  /// No active candidates.
  case searching
  /// Candidates exist but none verified yet.
  case verifying(candidateIDs: [CandidateID])
  /// A verified match is being tracked.
  case found(candidateID: CandidateID)
}
