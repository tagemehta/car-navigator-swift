//  MockDriftRepairService.swift
//  thing-finderTests
//
//  Mock implementation of DriftRepairServiceProtocol for unit tests.
//  Records tick calls and allows controlled behavior.

import CoreGraphics
import CoreVideo
import Vision

@testable import thing_finder

final class MockDriftRepairService: DriftRepairServiceProtocol {
  /// Records each call to tick() for verification
  private(set) var tickCallCount = 0

  /// Optional closure to execute custom behavior on tick
  var onTick:
    (
      (
        CVPixelBuffer, CGImagePropertyOrientation, CGSize, CGRect, [Detection],
        CandidateStore
      ) -> Void
    )?

  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    detections: [Detection],
    store: CandidateStore
  ) {
    tickCallCount += 1
    onTick?(pixelBuffer, orientation, imageSize, viewBounds, detections, store)
  }

  func reset() {
    tickCallCount = 0
    onTick = nil
  }
}
