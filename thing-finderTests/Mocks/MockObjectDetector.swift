//  MockObjectDetector.swift
//  thing-finderTests
//
//  Mock implementation of ObjectDetector for unit tests.
//  Returns canned detections and records calls for verification.

import CoreGraphics
import CoreVideo
import Vision

@testable import thing_finder

final class MockObjectDetector: ObjectDetector {
  /// Canned detections to return from detect()
  var cannedDetections: [Detection] = []

  /// Records each call to detect() for verification
  private(set) var detectCallCount = 0

  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    detectCallCount += 1
    return cannedDetections.filter(filter)
  }

  func reset() {
    detectCallCount = 0
    cannedDetections = []
  }
}
