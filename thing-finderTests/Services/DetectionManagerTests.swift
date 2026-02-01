//  DetectionManagerTests.swift
//  thing-finderTests
//
//  Unit tests for Detection wrapper and MockObjectDetector.
//  Note: DetectionManager itself requires a real VNCoreMLModel, but the Detection
//  wrapper abstraction allows testing of detection-consuming code.

import CoreGraphics
import XCTest

@testable import thing_finder

final class DetectionManagerTests: XCTestCase {

  // MARK: - Detection Wrapper Tests

  func test_detection_testInit_createsWithoutVision() {
    let detection = Detection(
      boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
      labels: [DetectionLabel(identifier: "car", confidence: 0.95)]
    )

    XCTAssertEqual(detection.boundingBox, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    XCTAssertEqual(detection.labels.count, 1)
    XCTAssertEqual(detection.labels.first?.identifier, "car")
    XCTAssertEqual(detection.labels.first?.confidence, 0.95)
    XCTAssertEqual(detection.confidence, 1.0)  // default
    XCTAssertNil(detection.observation)  // no Vision object
  }

  func test_detection_multipleLabels() {
    let detection = Detection(
      boundingBox: .zero,
      labels: [
        DetectionLabel(identifier: "car", confidence: 0.9),
        DetectionLabel(identifier: "truck", confidence: 0.7),
        DetectionLabel(identifier: "bus", confidence: 0.3),
      ]
    )

    XCTAssertEqual(detection.labels.count, 3)
    XCTAssertEqual(detection.labels[0].identifier, "car")
    XCTAssertEqual(detection.labels[1].identifier, "truck")
    XCTAssertEqual(detection.labels[2].identifier, "bus")
  }

  func test_detection_customConfidenceAndUuid() {
    let customUuid = UUID()
    let detection = Detection(
      boundingBox: .zero,
      labels: [],
      confidence: 0.85,
      uuid: customUuid
    )

    XCTAssertEqual(detection.confidence, 0.85)
    XCTAssertEqual(detection.uuid, customUuid)
  }

  // MARK: - DetectionLabel Tests

  func test_detectionLabel_init() {
    let label = DetectionLabel(identifier: "motorcycle", confidence: 0.88)

    XCTAssertEqual(label.identifier, "motorcycle")
    XCTAssertEqual(label.confidence, 0.88)
  }

  // MARK: - MockObjectDetector Tests

  func test_mockObjectDetector_returnsCannedDetections() {
    let mock = MockObjectDetector()
    let detection1 = Detection(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )
    let detection2 = Detection(
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3),
      labels: [DetectionLabel(identifier: "truck", confidence: 0.8)]
    )
    mock.cannedDetections = [detection1, detection2]

    let results = mock.detect(
      createTestPixelBuffer(),
      filter: { _ in true },
      orientation: .up
    )

    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(mock.detectCallCount, 1)
  }

  func test_mockObjectDetector_appliesFilter() {
    let mock = MockObjectDetector()
    mock.cannedDetections = [
      Detection(
        boundingBox: .zero,
        labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
      ),
      Detection(
        boundingBox: .zero,
        labels: [DetectionLabel(identifier: "truck", confidence: 0.8)]
      ),
      Detection(
        boundingBox: .zero,
        labels: [DetectionLabel(identifier: "car", confidence: 0.7)]
      ),
    ]

    let results = mock.detect(
      createTestPixelBuffer(),
      filter: { $0.labels.first?.identifier == "car" },
      orientation: .up
    )

    XCTAssertEqual(results.count, 2)
    XCTAssertTrue(results.allSatisfy { $0.labels.first?.identifier == "car" })
  }

  func test_mockObjectDetector_tracksCallCount() {
    let mock = MockObjectDetector()

    _ = mock.detect(createTestPixelBuffer(), filter: { _ in true }, orientation: .up)
    _ = mock.detect(createTestPixelBuffer(), filter: { _ in true }, orientation: .up)
    _ = mock.detect(createTestPixelBuffer(), filter: { _ in true }, orientation: .up)

    XCTAssertEqual(mock.detectCallCount, 3)
  }

  func test_mockObjectDetector_reset() {
    let mock = MockObjectDetector()
    mock.cannedDetections = [
      Detection(boundingBox: .zero, labels: [])
    ]
    _ = mock.detect(createTestPixelBuffer(), filter: { _ in true }, orientation: .up)

    mock.reset()

    XCTAssertEqual(mock.detectCallCount, 0)
    XCTAssertTrue(mock.cannedDetections.isEmpty)
  }

  // MARK: - Helpers

  private func createTestPixelBuffer() -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      100, 100,
      kCVPixelFormatType_32BGRA,
      nil,
      &pixelBuffer
    )
    precondition(status == kCVReturnSuccess && pixelBuffer != nil)
    return pixelBuffer!
  }
}
