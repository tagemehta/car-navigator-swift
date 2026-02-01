//  MockTrackingRequest.swift
//  thing-finderTests
//
//  Helper functions for creating TrackingRequest instances in tests.
//  Since TrackingRequest is now a struct, tests can create it directly.

import CoreGraphics
import Foundation

@testable import thing_finder

/// Convenience factory for creating test TrackingRequest instances
enum TestTrackingRequest {
  /// Creates a TrackingRequest for testing with the given bounding box
  static func make(
    id: UUID = UUID(),
    boundingBox: CGRect = .zero,
    isLastFrame: Bool = false
  ) -> TrackingRequest {
    TrackingRequest(id: id, boundingBox: boundingBox, isLastFrame: isLastFrame)
  }
}
