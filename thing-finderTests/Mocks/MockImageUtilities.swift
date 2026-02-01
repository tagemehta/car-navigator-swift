//  MockImageUtilities.swift
//  thing-finderTests
//
//  Mock implementation of ImageUtilities for testing.
//  Allows controlling blur score and other image processing results.

import CoreGraphics
import CoreVideo
import UIKit

@testable import thing_finder

/// Mock ImageUtilities that returns configurable values for testing.
class MockImageUtilities: ImageUtilities {

  /// The blur score to return from blurScore(from:).
  /// Set to a low value (< 0.1) to pass blur detection.
  var mockBlurScore: Double? = 0.05

  override func blurScore(from image: UIImage) -> Double? {
    return mockBlurScore
  }
}
