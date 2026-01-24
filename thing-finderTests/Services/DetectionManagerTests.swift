//  DetectionManagerTests.swift
//  thing-finderTests
//
//  Unit tests for DetectionManager.
//  Note: DetectionManager requires a real VNCoreMLModel and VNRecognizedObjectObservation
//  instances which cannot be easily mocked. Full testing requires integration tests
//  with real models and Vision framework.
//
//  This file documents the testing limitations and provides a placeholder for
//  future integration tests when the Vision testing strategy is implemented.

import CoreGraphics
import XCTest

@testable import thing_finder

final class DetectionManagerTests: XCTestCase {

  // MARK: - Documentation

  /// DetectionManager is tightly coupled to Vision/CoreML frameworks:
  /// - Requires VNCoreMLModel in init (needs real .mlmodel file)
  /// - detect() returns VNRecognizedObjectObservation (no public initializer)
  /// - stableDetections() depends on detect() results
  /// - findBestCandidate() takes VNRecognizedObjectObservation array
  ///
  /// Testing options for Phase 3+:
  /// 1. Integration tests with real model loaded from test bundle
  /// 2. Refactor to use ObjectDetector protocol (already exists) with mock
  /// 3. Create test fixtures with pre-recorded detection results
  ///
  /// For now, DetectionManager is tested via MockObjectDetector in other tests.

  func test_placeholder_documentationOnly() {
    // This test exists to document the testing limitations
    // Real tests will be added in Phase 3 integration testing
    XCTAssertTrue(true, "DetectionManager requires integration tests - see class documentation")
  }
}
