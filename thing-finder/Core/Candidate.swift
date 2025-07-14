//  Candidate.swift
//  Lightweight model representing a single detected object through its lifecycle.
//  This file is intentionally framework-agnostic (no ARKit/UI imports) so it can be
//  unit-tested on macOS as pure Swift.

import Foundation
import Vision

/// Match status as returned by the LLM verifier.
enum MatchStatus: Equatable {
  case unknown  // Verification not started yet
  case waiting // Verification started
  case matched  // LLM confirmed match (positive)
  case rejected  // LLM rejected match (negative)
}

/// Unique identifier typealias for readability
typealias CandidateID = UUID

/// Core data model for a candidate object.
/// It starts as Vision-only (bounding box + tracking request) and may be
/// "promoted" to ARKit once a successful raycast creates an anchor.
struct Candidate: Identifiable, Equatable {
  public let id: CandidateID

  // MARK: Tracking
  /// The VNTrackObjectRequest responsible for Vision tracking (rect-only)
  public var trackingRequest: VNTrackObjectRequest

  /// Optional ARAnchor UUID if/when the candidate is promoted to ARKit.
  public var anchorId: UUID?

  /// Last Vision boundingBox in image coordinates (0-1)
  public var lastBoundingBox: CGRect

  // MARK: Verification
  public var matchStatus: MatchStatus = .unknown

  // MARK: Lifetime bookkeeping
  public var createdAt = Date()
  public var lastUpdated = Date()

  public init(
    id: CandidateID = UUID(),
    trackingRequest: VNTrackObjectRequest,
    boundingBox: CGRect
  ) {
    self.id = id
    self.trackingRequest = trackingRequest
    self.lastBoundingBox = boundingBox
  }
}
