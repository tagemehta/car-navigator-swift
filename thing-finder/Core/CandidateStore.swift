//  CandidateStore.swift
//  thing-finder
//
//  Observable collection of candidates accessed by all pipeline services.
//  Thread-safe with main-thread publishes for SwiftUI.
//
//  NOTE: Mutation helpers are now **internally main-queue synchronized**.
//  Callers can safely invoke them from any thread.  All writes are performed
//  on the main thread using a lightweight synchronous hop.

import Combine
import CoreGraphics
import Foundation
import Vision

/// Store publishes snapshots so observers have value-type semantics.
public final class CandidateStore: ObservableObject {
  // MARK: - Thread-safety helper
  /// Executes `block` synchronously on the main thread, returning its result.
  /// If already on the main thread the block is executed directly to avoid
  /// unnecessary context switching.
  @inline(__always) @discardableResult
  private func syncOnMain<R>(_ block: () -> R) -> R {
    if Thread.isMainThread {
      return block()
    } else {
      return DispatchQueue.main.sync(execute: block)
    }
  }

  /// Current candidates keyed by id.
  @Published private(set) public var candidates: [CandidateID: Candidate] = [:]

  public init() {}

  // MARK: Mutation helpers
  public func upsert(_ candidate: Candidate) {
    syncOnMain { candidates[candidate.id] = candidate }
  }

  public func remove(id: CandidateID) {
    syncOnMain { candidates.removeValue(forKey: id) }
  }

  public func update(id: CandidateID, _ modify: (inout Candidate) -> Void) {
    syncOnMain {
      guard var value = candidates[id] else { return }
      modify(&value)
      value.lastUpdated = Date()
      candidates[id] = value
    }
  }

  public func clear() {
    syncOnMain { candidates.removeAll() }
  }

  /// Enforce single-winner invariant: at most one candidate can be `.full` at a time.
  /// Users get into one rideshare, not multiple – multiple simultaneous targets is unsupported.
  /// Keeps the most recently updated matched candidate and removes all others.
  public func pruneToSingleMatched() {
    let matched = candidates.values.filter { $0.isMatched }
    guard let winner = matched.max(by: { $0.lastUpdated < $1.lastUpdated }) else { return }
    syncOnMain {
      for (id, cand) in candidates where id != winner.id || cand.matchStatus == .lost {
        candidates.removeValue(forKey: id)
      }
    }
  }

  /// Check if `bbox` likely represents the same object as an existing candidate.
  /// Uses IoU (intersection-over-union) and center distance to prevent creating
  /// duplicate candidates for the same physical object.
  /// - Parameters:
  ///   - iouThreshold: Boxes with IoU above this are considered duplicates. Empirically tuned.
  ///   - centerDistanceThreshold: Normalized distance (0-1). Empirically tuned.
  public func containsDuplicateOf(
    _ bbox: CGRect, iouThreshold: CGFloat = 0.6, centerDistanceThreshold: CGFloat = 0.15
  ) -> Bool {
    for cand in candidates.values {
      // Check IoU overlap first (fast)
      if cand.matchStatus == .lost { continue }
      if cand.lastBoundingBox.iou(with: bbox) > iouThreshold {
        return true
      }

      // If IoU check passes, also check center distance (handles cases where boxes shifted but centers close)
      let centerX1 = Double(bbox.midX)
      let centerY1 = Double(bbox.midY)
      let centerX2 = Double(cand.lastBoundingBox.midX)
      let centerY2 = Double(cand.lastBoundingBox.midY)

      let distance = sqrt(pow(centerX1 - centerX2, 2) + pow(centerY1 - centerY2, 2))
      if distance < Double(centerDistanceThreshold) {
        return true
      }
    }
    return false
  }

  public subscript(id: CandidateID) -> Candidate? {
    get { candidates[id] }
    set {
      syncOnMain { candidates[id] = newValue }
    }
  }
  /// Thread-safe read-only snapshot of the current candidates.
  /// Always executed on the main queue to avoid data races.
  func snapshot() -> [CandidateID: Candidate] {
    syncOnMain { candidates }
  }
}

extension CandidateStore {
  var hasActiveMatch: Bool {
    candidates.values.contains { $0.matchStatus == .full }
  }
}
