//  MockVerifierService.swift
//  thing-finderTests
//
//  Mock implementation of VerifierServiceProtocol for unit tests.
//  Records tick calls and allows controlled behavior.

import CoreGraphics
import CoreVideo
import Vision

@testable import thing_finder

final class MockVerifierService: VerifierServiceProtocol {
  /// Records each call to tick() for verification
  private(set) var tickCallCount = 0

  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    store: CandidateStore
  ) {
    tickCallCount += 1
  }

  func reset() {
    tickCallCount = 0
  }
}
