//  TrackingRequest.swift
//  thing-finder
//
//  Protocol abstracting Vision's VNTrackObjectRequest for testability.
//  Production code uses VNTrackObjectRequest directly; tests can substitute
//  a lightweight mock without importing Vision framework.

import CoreGraphics
import Foundation
import Vision

/// Abstraction over a tracking request for testability.
/// Production uses `VNTrackObjectRequest`; tests use `MockTrackingRequest`.
public protocol TrackingRequest: AnyObject {
  /// The current bounding box being tracked (normalized 0-1 coordinates).
  var boundingBox: CGRect { get }
  /// Whether this is the final frame for tracking (request should be removed).
  var isLastFrame: Bool { get set }
}

// MARK: - VNTrackObjectRequest conformance

extension VNTrackObjectRequest: TrackingRequest {
  public var boundingBox: CGRect {
    (inputObservation as? VNDetectedObjectObservation)?.boundingBox ?? .zero
  }
}
