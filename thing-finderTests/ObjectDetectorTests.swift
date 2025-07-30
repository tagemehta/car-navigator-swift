import XCTest
import Vision
@testable import thing_finder

/// A minimal, deterministic `ObjectDetector` implementation used *only* for unit testing the
/// contract expected by the coordinator: it passes Vision observations through a confidence
/// threshold and caller‐supplied filter closure.
private final class DummyDetector: ObjectDetector {
  /// Stubbed observations returned on each `detect` call. Tests mutate this directly.
  var stubObservations: [VNRecognizedObjectObservation] = []
  /// Optional error simulation – when `true` `detect` returns an empty array emulating a model failure.
  var simulateFailure = false
  /// Confidence threshold (defaults to 0.5 like many MobileNet models).
  var confidenceThreshold: VNConfidence = 0.5

  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: (VNRecognizedObjectObservation) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [VNRecognizedObjectObservation] {
    guard !simulateFailure else { return [] }
    return stubObservations
      .filter { $0.confidence >= confidenceThreshold }
      .filter(filter)
  }
}

/// Simple helper to craft a `VNRecognizedObjectObservation` with given confidence.
private func makeObservation(confidence: VNConfidence = 0.9,
                             boundingBox: CGRect = CGRect(x: 0, y: 0, width: 0.2, height: 0.2))
  -> VNRecognizedObjectObservation {
  // VNRecognizedObjectObservation’s designated initializer only takes a bbox; confidence is KVC-settable.
  let obs = VNRecognizedObjectObservation(boundingBox: boundingBox)
  obs.setValue(confidence, forKey: "confidence")
  return obs
}

final class ObjectDetectorTests: XCTestCase {
  private var detector: DummyDetector!
  private var pixelBuffer: CVPixelBuffer!

  override func setUp() {
    super.setUp()
    detector = DummyDetector()
    // Minimal 1×1 buffer – we never read pixels in DummyDetector.
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)
    pixelBuffer = pb!
  }

  // MARK: - 1. Confidence filtering
  func test_detect_filtersByConfidence() {
    detector.confidenceThreshold = 0.5
    detector.stubObservations = [
      makeObservation(confidence: 0.95),
      makeObservation(confidence: 0.40)
    ]
    let results = detector.detect(pixelBuffer, filter: { _ in true }, orientation: .up)
    XCTAssertEqual(results.count, 1)
    XCTAssertTrue(results.allSatisfy { $0.confidence >= 0.5 })
  }

  // MARK: - 2. Caller filter closure respected
  func test_detect_respectsFilterClosure() {
    detector.stubObservations = [
      makeObservation(confidence: 0.9, boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1)),
      makeObservation(confidence: 0.9, boundingBox: CGRect(x: 0.6, y: 0.6, width: 0.1, height: 0.1))
    ]
    // Only keep observations in the top-left quadrant.
    let results = detector.detect(pixelBuffer, filter: { $0.boundingBox.midX < 0.5 }, orientation: .up)
    XCTAssertEqual(results.count, 1)
    XCTAssertTrue(results.allSatisfy { $0.boundingBox.midX < 0.5 })
  }

  // MARK: - 3. Model failure returns empty array
  func test_detect_returnsEmptyOnFailure() {
    detector.simulateFailure = true
    detector.stubObservations = [makeObservation()]  // should be ignored
    let results = detector.detect(pixelBuffer, filter: { _ in true }, orientation: .up)
    XCTAssertTrue(results.isEmpty)
  }
}
