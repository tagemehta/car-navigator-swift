//  MockTrackingRequest.swift
//  thing-finderTests
//
//  Lightweight mock for TrackingRequest protocol used in unit tests.
//  Avoids Vision framework dependency for fast, isolated testing.

import CoreGraphics

@testable import thing_finder

final class MockTrackingRequest: TrackingRequest {
  var boundingBox: CGRect
  var isLastFrame: Bool

  init(boundingBox: CGRect = .zero, isLastFrame: Bool = false) {
    self.boundingBox = boundingBox
    self.isLastFrame = isLastFrame
  }
}
