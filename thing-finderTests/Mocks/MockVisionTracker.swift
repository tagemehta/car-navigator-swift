//  MockVisionTracker.swift
//  thing-finderTests
//
//  Mock implementation of VisionTracker for unit tests.
//  Records tick calls and allows controlled behavior.

import CoreGraphics
import CoreVideo
import ImageIO

@testable import thing_finder

final class MockVisionTracker: VisionTracker {
  /// Records each call to tick() for verification
  private(set) var tickCallCount = 0

  /// Optional closure to execute custom behavior on tick
  var onTick: ((CVPixelBuffer, CGImagePropertyOrientation, CandidateStore) -> Void)?

  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    store: CandidateStore
  ) {
    tickCallCount += 1
    onTick?(pixelBuffer, orientation, store)
  }

  func reset() {
    tickCallCount = 0
    onTick = nil
  }
}
