//  TrackingRequest.swift
//  thing-finder
//
//  Wrapper struct abstracting Vision's VNTrackObjectRequest for testability.
//  Production code creates from VNTrackObjectRequest; tests create directly.

import CoreGraphics
import Foundation
import Vision

/// Wrapper for tracking requests. Can be created from `VNTrackObjectRequest` or directly in tests.
/// Uses a unique ID for identity comparison since the wrapper is a value type.
public struct TrackingRequest: Identifiable {
  /// Unique identifier for this tracking request (used for matching in TrackingManager)
  public let id: UUID

  /// The current bounding box being tracked (normalized 0-1 coordinates).
  public var boundingBox: CGRect

  /// Whether this is the final frame for tracking (request should be removed).
  public var isLastFrame: Bool

  /// The underlying Vision request, if this was created from one.
  /// Used when we need to perform actual Vision tracking.
  public let visionRequest: VNTrackObjectRequest?

  /// Create from a Vision request (production use)
  public init(from request: VNTrackObjectRequest) {
    self.id = UUID()
    self.boundingBox =
    (request.inputObservation as VNDetectedObjectObservation).boundingBox
    self.isLastFrame = request.isLastFrame
    self.visionRequest = request
  }

  /// Create directly (test use)
  public init(
    id: UUID = UUID(),
    boundingBox: CGRect = .zero,
    isLastFrame: Bool = false
  ) {
    self.id = id
    self.boundingBox = boundingBox
    self.isLastFrame = isLastFrame
    self.visionRequest = nil
  }
}

// MARK: - Equatable

extension TrackingRequest: Equatable {
  public static func == (lhs: TrackingRequest, rhs: TrackingRequest) -> Bool {
    lhs.id == rhs.id
  }
}
