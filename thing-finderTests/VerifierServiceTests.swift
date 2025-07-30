import XCTest
import Combine
import Vision
@testable import thing_finder

// MARK: - Test Helpers

/// Mock verifier that conforms to `ImageVerifier` and returns predetermined outcomes
/// Lightweight mock that conforms to `ImageVerifier` without subclassing.
private final class MockVerifier2: ImageVerifier {
  var targetClasses: [String] = ["car"]
  var targetTextDescription: String = "A car"

  // Configurable outcome to emit
  var nextOutcome: VerificationOutcome = VerificationOutcome(isMatch: true, description: "A car", rejectReason: nil)
  var verifyCalls = 0

  func verify(image: UIImage) -> AnyPublisher<VerificationOutcome, Error> {
    verifyCalls += 1
    return Just(nextOutcome)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }
  
  func timeSinceLastVerification() -> TimeInterval {
    return 100.0 // Always return a large interval to avoid rate limiting
  }
}

/// Minimal pixel buffer for testing
private func makePixelBuffer() -> CVPixelBuffer {
  var pb: CVPixelBuffer?; CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)
  return pb!
}

/// Creates a test candidate with unknown match status
private func makeCandidate() -> Candidate {
  let bbox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
  let obs = VNDetectedObjectObservation(boundingBox: bbox)
  let req = VNTrackObjectRequest(detectedObjectObservation: obs)
  return Candidate(trackingRequest: req, boundingBox: bbox)
}

// MARK: - Tests

final class VerifierServiceTests: XCTestCase {
  private var mockVerifier: MockVerifier2!
  private var service: VerifierService!
  private var store: CandidateStore!
  private var cancellables: Set<AnyCancellable> = []
  
  override func setUp() {
    super.setUp()
    mockVerifier = MockVerifier2()
    let config = VerificationConfig(
      expectedPlate: nil,
      maxOCRRetries: 2,
      cooldownAfterRejectSecs: 1.0,
      shouldRunOCR: false
    )
    service = VerifierService(verifier: mockVerifier, imgUtils: ImageUtilities.shared, config: config)
    store = CandidateStore()
  }
  
  override func tearDown() {
    cancellables.removeAll()
    super.tearDown()
  }
  
  // MARK: - Test Cases
  
  /// Test that unknown candidates are moved to waiting during verification
  func test_tick_setsUnknownCandidatesToWaiting() {
    // Setup candidate
    let candidate = makeCandidate()
    store.upsert(candidate)
    
    // Configure mock to delay response
    let expectation = XCTestExpectation(description: "Waiting state")
    mockVerifier.nextOutcome = VerificationOutcome(isMatch: true, description: "A car", rejectReason: nil)
    
    // Observe store changes
    store.$candidates.sink { candidates in
      if candidates[candidate.id]?.matchStatus == .waiting {
        expectation.fulfill()
      }
    }.store(in: &cancellables)
    
    // Run tick
    service.tick(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      store: store
    )
    
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(mockVerifier.verifyCalls, 1)
  }
  
  /// Test that matched candidates progress to full status
  func test_tick_setsMatchedCandidatesToFull() {
    // Setup candidate
    let candidate = makeCandidate()
    store.upsert(candidate)
    
    // Configure mock for success
    let expectation = XCTestExpectation(description: "Full match")
    mockVerifier.nextOutcome = VerificationOutcome(isMatch: true, description: "A car", rejectReason: nil)
    
    // Observe store changes
    store.$candidates.sink { candidates in
      if candidates[candidate.id]?.matchStatus == .full {
        expectation.fulfill()
      }
    }.store(in: &cancellables)
    
    // Run tick
    service.tick(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      store: store
    )
    
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(mockVerifier.verifyCalls, 1)
  }
  
  /// Test that non-matched candidates are rejected
  func test_tick_setsNonMatchedCandidatesToRejected() {
    // Setup candidate
    let candidate = makeCandidate()
    store.upsert(candidate)
    
    // Configure mock for rejection
    let expectation = XCTestExpectation(description: "Rejection")
    mockVerifier.nextOutcome = VerificationOutcome(
      isMatch: false, 
      description: "Not a car", 
      rejectReason: "wrong_object"
    )
    
    // Observe store changes
    store.$candidates.sink { candidates in
      if candidates[candidate.id]?.matchStatus == .rejected {
        expectation.fulfill()
      }
    }.store(in: &cancellables)
    
    // Run tick
    service.tick(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      store: store
    )
    
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(mockVerifier.verifyCalls, 1)
    XCTAssertEqual(store[candidate.id]?.rejectReason, "wrong_object")
  }
  
  /// Test that unclear images stay in unknown state for retry
  func test_tick_keepsUnclearImagesAsUnknown() {
    // Setup candidate
    let candidate = makeCandidate()
    store.upsert(candidate)
    
    // Configure mock for unclear image
    let expectation = XCTestExpectation(description: "Unclear image")
    mockVerifier.nextOutcome = VerificationOutcome(
      isMatch: false, 
      description: "Image is blurry", 
      rejectReason: "unclear_image"
    )
    
    // First observe waiting state
    var waitingObserved = false
    store.$candidates.sink { candidates in
      if candidates[candidate.id]?.matchStatus == .waiting {
        waitingObserved = true
      } else if waitingObserved && candidates[candidate.id]?.matchStatus == .unknown {
        expectation.fulfill()
      }
    }.store(in: &cancellables)
    
    // Run tick
    service.tick(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      store: store
    )
    
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(mockVerifier.verifyCalls, 1)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .unknown)
  }
  
  /// Test OCR progression when enabled
  func test_tick_withOCR_progressesThroughPartialState() {
    // Setup with OCR enabled
    let config = VerificationConfig(
      expectedPlate: nil,
      maxOCRRetries: 2,
      cooldownAfterRejectSecs: 1.0,
      shouldRunOCR: true
    )
    service = VerifierService(verifier: mockVerifier, imgUtils: ImageUtilities.shared, config: config)
    
    // Setup candidate
    let candidate = makeCandidate()
    store.upsert(candidate)
    
    // Configure mock for match
    let expectation = XCTestExpectation(description: "Partial match")
    mockVerifier.nextOutcome = VerificationOutcome(isMatch: true, description: "A car", rejectReason: nil)
    
    // Observe store changes to partial
    store.$candidates.sink { candidates in
      if candidates[candidate.id]?.matchStatus == .partial {
        expectation.fulfill()
      }
    }.store(in: &cancellables)
    
    // Run tick
    service.tick(
      pixelBuffer: makePixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 1, height: 1),
      viewBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
      store: store
    )
    
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(mockVerifier.verifyCalls, 1)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .partial)
  }
}
