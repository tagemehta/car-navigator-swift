//  MockCandidateLifecycleService.swift
//  thing-finderTests
//
//  Mock implementation of CandidateLifecycleServiceProtocol for unit tests.
//  Records tick calls and allows controlled behavior.

import CoreGraphics
import CoreVideo
import Vision

@testable import thing_finder

final class MockCandidateLifecycleService: CandidateLifecycleServiceProtocol {
  /// Records each call to tick() for verification
  private(set) var tickCallCount = 0

  /// Value returned by tick(); simulates "all candidates lost" when true.
  var isLostToReturn = false

  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    detections: [Detection],
    store: CandidateStore
  ) -> Bool {
    tickCallCount += 1
    return isLostToReturn
  }

  func reset() {
    tickCallCount = 0
    isLostToReturn = false
  }
}
