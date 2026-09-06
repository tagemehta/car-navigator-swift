//  FramePipelineCoordinatorTests.swift
//  thing-finderTests
//
//  Regression coverage for the per-frame depth-sampling coordinate mapping
//  in `FramePipelineCoordinator.process`. In particular, ARKit sample
//  points must be converted into the preview view's own coordinate system
//  (as `ARView.makeRaycastQuery(from:)` requires) rather than passed
//  through as raw normalized Vision coordinates.

import CoreGraphics
import CoreVideo
import Vision
import XCTest

@testable import thing_finder

final class FramePipelineCoordinatorTests: XCTestCase {

  private var detector: MockObjectDetector!
  private var tracker: MockVisionTracker!
  private var driftRepair: MockDriftRepairService!
  private var verifier: MockVerifierService!
  private var lifecycle: MockCandidateLifecycleService!
  private var nav: MockNavigationSpeaker!
  private var store: CandidateStore!
  private var settings: Settings!

  override func setUp() {
    super.setUp()
    detector = MockObjectDetector()
    tracker = MockVisionTracker()
    driftRepair = MockDriftRepairService()
    verifier = MockVerifierService()
    lifecycle = MockCandidateLifecycleService()
    nav = MockNavigationSpeaker()
    store = CandidateStore()
    settings = TestSettings.makeDefault()
  }

  override func tearDown() {
    detector = nil
    tracker = nil
    driftRepair = nil
    verifier = nil
    lifecycle = nil
    nav = nil
    store = nil
    settings = nil
    super.tearDown()
  }

  private func makeCoordinator() -> FramePipelineCoordinator {
    FramePipelineCoordinator(
      detector: detector,
      tracker: tracker,
      driftRepair: driftRepair,
      verifier: verifier,
      nav: nav,
      store: store,
      lifecycle: lifecycle,
      targetClasses: ["car"],
      targetDescription: "test car",
      settings: settings
    )
  }

  /// Seeds the store with a single fully-matched, fresh candidate so the
  /// coordinator's state machine reaches `.found` and samples depth for it.
  private func seedMatchedCandidate(boundingBox: CGRect) -> Candidate {
    var candidate = Candidate(
      trackingRequest: TestTrackingRequest.make(boundingBox: boundingBox),
      boundingBox: boundingBox
    )
    candidate.matchStatus = .full
    candidate.missCount = 0
    store.upsert(candidate)
    return candidate
  }

  private func createTestPixelBuffer(width: Int = 100, height: Int = 100) -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width, height,
      kCVPixelFormatType_32BGRA,
      nil,
      &pixelBuffer
    )
    precondition(status == kCVReturnSuccess && pixelBuffer != nil)
    return pixelBuffer!
  }

  /// The exact sample offsets used internally by the coordinator when
  /// building depth-sample points from a candidate's bounding box.
  private let sampleOffsets: [CGPoint] = [
    CGPoint(x: 0.5, y: 0.5),
    CGPoint(x: 0.25, y: 0.5),
    CGPoint(x: 0.75, y: 0.5),
    CGPoint(x: 0.5, y: 0.25),
    CGPoint(x: 0.5, y: 0.75),
  ]

  /// Recomputes the expected ARKit sample points using the same
  /// `ImageUtilities.unscaledBoundingBoxes` mapping the production code is
  /// expected to use, so this test would fail against a version that skips
  /// that conversion (e.g. by forwarding raw normalized points).
  private func expectedARKitPoints(
    box: CGRect,
    imageSize: CGSize,
    viewSize: CGSize,
    orientation: CGImagePropertyOrientation
  ) -> [CGPoint] {
    sampleOffsets.map { offset in
      let point = CGPoint(
        x: box.minX + box.width * offset.x,
        y: box.minY + box.height * offset.y)
      let sampleRect = CGRect(
        x: point.x,
        y: point.y,
        width: max(box.width * 0.01, 0.0001),
        height: max(box.height * 0.01, 0.0001))
      let (_, viewRect) = ImageUtilities.shared.unscaledBoundingBoxes(
        for: sampleRect,
        imageSize: imageSize,
        viewSize: viewSize,
        orientation: orientation)
      return CGPoint(x: viewRect.midX, y: viewRect.midY)
    }
  }

  // MARK: - ARKit: portrait, non-square preview bounds

  func test_arKit_portrait_samplesConvertedToViewCoordinates() {
    let box = CGRect(x: 0.35, y: 0.05, width: 0.3, height: 0.15)
    let imageSize = CGSize(width: 1920, height: 1080)
    let viewBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let orientation: CGImagePropertyOrientation = .right
    _ = seedMatchedCandidate(boundingBox: box)

    var capturedPoints: [CGPoint] = []
    let coordinator = makeCoordinator()
    coordinator.process(
      pixelBuffer: createTestPixelBuffer(),
      orientation: orientation,
      imageSize: imageSize,
      viewBounds: viewBounds,
      depthAt: { points in
        capturedPoints = points
        return points.map { _ in Float(5.0) }
      },
      captureType: .arKit
    )

    let expected = expectedARKitPoints(
      box: box, imageSize: imageSize, viewSize: viewBounds.size, orientation: orientation)

    XCTAssertEqual(capturedPoints.count, expected.count)
    for (captured, exp) in zip(capturedPoints, expected) {
      XCTAssertEqual(captured.x, exp.x, accuracy: 1e-6)
      XCTAssertEqual(captured.y, exp.y, accuracy: 1e-6)
    }

    // Regression guard: points must fall within the preview's own bounds,
    // not be raw 0-1 normalized values (which would all sit in the
    // top-left corner of a 390x844 view).
    for point in capturedPoints {
      XCTAssertTrue(viewBounds.contains(point), "Point \(point) is outside view bounds")
    }
  }

  // MARK: - ARKit: landscape, non-square preview bounds

  func test_arKit_landscape_samplesConvertedToViewCoordinates() {
    let box = CGRect(x: 0.1, y: 0.6, width: 0.25, height: 0.2)
    let imageSize = CGSize(width: 1920, height: 1080)
    let viewBounds = CGRect(x: 0, y: 0, width: 844, height: 390)
    let orientation: CGImagePropertyOrientation = .up
    _ = seedMatchedCandidate(boundingBox: box)

    var capturedPoints: [CGPoint] = []
    let coordinator = makeCoordinator()
    coordinator.process(
      pixelBuffer: createTestPixelBuffer(),
      orientation: orientation,
      imageSize: imageSize,
      viewBounds: viewBounds,
      depthAt: { points in
        capturedPoints = points
        return points.map { _ in Float(5.0) }
      },
      captureType: .arKit
    )

    let expected = expectedARKitPoints(
      box: box, imageSize: imageSize, viewSize: viewBounds.size, orientation: orientation)

    XCTAssertEqual(capturedPoints.count, expected.count)
    for (captured, exp) in zip(capturedPoints, expected) {
      XCTAssertEqual(captured.x, exp.x, accuracy: 1e-6)
      XCTAssertEqual(captured.y, exp.y, accuracy: 1e-6)
    }

    for point in capturedPoints {
      XCTAssertTrue(viewBounds.contains(point), "Point \(point) is outside view bounds")
    }
  }

  // MARK: - ARKit: points must not equal raw normalized coordinates

  func test_arKit_samplesAreNotRawNormalizedPoints() {
    // A box far from the image origin. If the bug (forwarding normalized
    // points unconverted) were present, sampled points would sit near
    // (0.3, 0.6) instead of being scaled into the much larger view bounds.
    let box = CGRect(x: 0.25, y: 0.55, width: 0.1, height: 0.1)
    let imageSize = CGSize(width: 1920, height: 1080)
    let viewBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    _ = seedMatchedCandidate(boundingBox: box)

    var capturedPoints: [CGPoint] = []
    let coordinator = makeCoordinator()
    coordinator.process(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .right,
      imageSize: imageSize,
      viewBounds: viewBounds,
      depthAt: { points in
        capturedPoints = points
        return points.map { _ in Float(5.0) }
      },
      captureType: .arKit
    )

    XCTAssertFalse(capturedPoints.isEmpty)
    for point in capturedPoints {
      // Raw normalized coordinates are always <= 1.0 in both axes; real
      // view-space points for a 390x844 preview should exceed that.
      XCTAssertTrue(
        point.x > 1.0 || point.y > 1.0,
        "Point \(point) looks like an unconverted normalized coordinate")
    }
  }

  // MARK: - AVFoundation: sample points remain normalized depth-map coordinates

  func test_avFoundation_samplesRemainNormalized() {
    let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
    let imageSize = CGSize(width: 1920, height: 1080)
    let viewBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    _ = seedMatchedCandidate(boundingBox: box)

    var capturedPoints: [CGPoint] = []
    let coordinator = makeCoordinator()
    coordinator.process(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .right,
      imageSize: imageSize,
      viewBounds: viewBounds,
      depthAt: { points in
        capturedPoints = points
        return points.map { _ in Float(5.0) }
      },
      captureType: .avFoundation
    )

    XCTAssertEqual(capturedPoints.count, sampleOffsets.count)
    for point in capturedPoints {
      XCTAssertTrue((0...1).contains(point.x), "x=\(point.x) should stay normalized")
      XCTAssertTrue((0...1).contains(point.y), "y=\(point.y) should stay normalized")
    }
  }
}
