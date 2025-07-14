//  CandidateStore.swift
//  Observable collection of candidates accessed by all pipeline services.
//  Thread-safe with main-thread publishes for SwiftUI.

import Combine
import Foundation

/// Store publishes snapshots so observers have value-type semantics.
final class CandidateStore: ObservableObject {
  /// Current candidates keyed by id.
  @Published private(set) public var candidates: [CandidateID: Candidate] = [:]

  public init() {}

  // MARK: Mutation helpers
  public func upsert(_ candidate: Candidate) {
    candidates[candidate.id] = candidate
  }

  public func remove(id: CandidateID) {
    candidates.removeValue(forKey: id)
  }

  public func update(id: CandidateID, _ modify: (inout Candidate) -> Void) {
    guard var value = candidates[id] else { return }
    modify(&value)
    value.lastUpdated = Date()
    candidates[id] = value
  }

  public func clear() { candidates.removeAll() }
}
