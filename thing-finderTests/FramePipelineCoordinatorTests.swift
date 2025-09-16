import CoreGraphics
import CoreMedia
import Vision
import XCTest

@testable import thing_finder

// MARK: - Mocks

final class MockDetector: ObjectDetector {
  var detectCallCount = 0
  var stubObservations: [VNRecognizedObjectObservation] = []
  func detect(
    _ pixelBuffer: CVPixelBuffer, filter: (VNRecognizedObjectObservation) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [VNRecognizedObjectObservation] {
    detectCallCount += 1
    return stubObservations
  }
}

final class MockTracker: VisionTracker {
  var tickCallCount = 0
  func tick(
    pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, store: CandidateStore
  ) {
    tickCallCount += 1
  }
}

final class MockDriftRepair: DriftRepairServiceProtocol {
  var tickCallCount = 0
  func tick(
    pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, imageSize: CGSize,
    viewBounds: CGRect, detections: [VNRecognizedObjectObservation], store: CandidateStore
  ) {
    tickCallCount += 1
  }
}

final class MockVerifier: VerifierServiceProtocol {
  var tickCallCount = 0
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    store: CandidateStore
  ) {
    tickCallCount += 1
    // Advance each candidate's matchStatus exactly one step per tick.
    for id in store.candidates.keys {
      store.update(id: id) { candidate in
        switch candidate.matchStatus {
        case .unknown:
          candidate.matchStatus = .waiting
        case .waiting:
          candidate.matchStatus = .partial
        case .partial:
          candidate.matchStatus = .full
        case .full:
          break  // already done
        case .rejected:
          break
        }
      }
    }
  }
}

final class MockNav: NavigationSpeaker {
  struct TickArgs {
    let candidates: [Candidate]
    let targetBox: CGRect?
  }
  var tickCallCount = 0
  var lastArgs: TickArgs?
  func tick(at timestamp: Date, candidates: [Candidate], targetBox: CGRect?, distance: Double?) {
    tickCallCount += 1
    lastArgs = TickArgs(candidates: candidates, targetBox: targetBox)
  }
}

final class MockLifecycle: CandidateLifecycleServiceProtocol {
  var tickCallCount = 0
  var stubIsLost: Bool = false
  func tick(
    pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, imageSize: CGSize,
    detections: [VNRecognizedObjectObservation], store: CandidateStore
  ) -> Bool {
    tickCallCount += 1
    // Mimic ingestion: each detection becomes / updates a candidate in the store.
    for det in detections {
      let req = VNTrackObjectRequest(detectedObjectObservation: det)
      let candidate = Candidate(trackingRequest: req, boundingBox: det.boundingBox)
      store.upsert(candidate)
    }
    return stubIsLost
  }
}

// Helper to create a 1×1 pixelBuffer for tests
private func makePixelBuffer() -> CVPixelBuffer {
  var pb: CVPixelBuffer?
  CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)
  return pb!
}

// MARK: - Tests

final class FramePipelineCoordinatorTests: XCTestCase {
  private var detector: MockDetector!
  private var tracker: MockTracker!
  private var drift: MockDriftRepair!
  private var verifier: MockVerifier!
  private var nav: MockNav!
  private var lifecycle: MockLifecycle!
  private var coordinator: FramePipelineCoordinator!
  private var store: CandidateStore!

  override func setUp() {
    super.setUp()
    detector = MockDetector()
    tracker = MockTracker()
    drift = MockDriftRepair()
    verifier = MockVerifier()
    nav = MockNav()
    lifecycle = MockLifecycle()
    store = CandidateStore()
    coordinator = FramePipelineCoordinator(
      detector: detector,
      tracker: tracker,
      driftRepair: drift,
      verifier: verifier,
      nav: nav,
      store: store,
      lifecycle: lifecycle,
      targetClasses: ["car"],
      targetDescription: "blue sedan",
      settings: Settings()
    )
  }

  // 1. Wiring – every service should be invoked exactly once per process call
  func test_process_invokesAllServicesOnce() {
    coordinator.process(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: .zero,
      depthAt: { _ in nil },
      captureType: .avFoundation
    )
    XCTAssertEqual(detector.detectCallCount, 1)
    XCTAssertEqual(tracker.tickCallCount, 1)
    XCTAssertEqual(drift.tickCallCount, 1)
    XCTAssertEqual(verifier.tickCallCount, 1)
    XCTAssertEqual(lifecycle.tickCallCount, 1)
    XCTAssertEqual(nav.tickCallCount, 1)
  }

  // 2. No candidates → searching phase
  func test_presentation_publishedWhenNoCandidates() {
    XCTAssertNil(coordinator.presentation)
    coordinator.process(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: .zero,
      depthAt: { _ in nil },
      captureType: .avFoundation
    )
    guard let presentation = coordinator.presentation else {
      XCTFail("presentation not published")
      return
    }
    if case .searching = presentation.phase {
      // ok
    } else {
      XCTFail("Expected .searching, got \(presentation.phase)")
    }
  }

  // 3. Transition verifying → found
  func test_phase_becomesFoundAfterProgressiveVerification() {
    // Detector returns a dummy observation; MockVerifier will immediately mark it as matched.
    let observation = VNRecognizedObjectObservation(
      boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))
    detector.stubObservations = [observation]

    // Run the pipeline up to 3 more times to allow status to progress to .full
    var attempts = 0
    while attempts < 3 {
      coordinator.process(
        pixelBuffer: makePixelBuffer(),
        orientation: .up,
        imageSize: CGSize(width: 1, height: 1),
        viewBounds: .zero,
        depthAt: { _ in nil },
        captureType: .avFoundation
      )
      if case .found = coordinator.presentation?.phase {
        break
      }
      attempts += 1
    }
    guard let finalPresentation = coordinator.presentation else {
      XCTFail()
      return
    }
    guard case .found = finalPresentation.phase else {
      XCTFail("not promoted to found")
      return
    }

  }

  // 4. Navigation receives target box when found
  func test_navigationTick_receivesTargetBoxWhenFound() {
    // Prepare candidate already matched
    let bbox = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
    let req = VNTrackObjectRequest(
      detectedObjectObservation: VNDetectedObjectObservation(boundingBox: bbox))
    let cand = Candidate(trackingRequest: req, boundingBox: bbox)
    store.upsert(cand)
    store.update(id: cand.id) { $0.matchStatus = .full }

    coordinator.process(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: .zero,
      depthAt: { _ in nil },
      captureType: .avFoundation
    )
    XCTAssertEqual(nav.tickCallCount, 1)
    XCTAssertNotNil(nav.lastArgs?.targetBox)
  }
}
