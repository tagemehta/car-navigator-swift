//  TrafficEyeVerifierTests.swift
//  thing-finderTests
//
//  Unit tests for TrafficEyeVerifier.
//  Tests blur detection, API response parsing, and verification outcomes.

import Combine
import XCTest

@testable import thing_finder

final class TrafficEyeVerifierTests: XCTestCase {

  private var mockURLSession: MockURLSession!
  private var mockImageUtils: MockImageUtilities!
  private var cancellables: Set<AnyCancellable>!

  override func setUp() {
    super.setUp()
    mockURLSession = MockURLSession()
    mockImageUtils = MockImageUtilities()
    mockImageUtils.mockBlurScore = 0.05  // Pass blur detection by default
    cancellables = []
  }

  override func tearDown() {
    mockURLSession = nil
    mockImageUtils = nil
    cancellables = nil
    super.tearDown()
  }

  // MARK: - Initialization

  func test_init_setsTargetDescription() {
    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda civic",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    XCTAssertEqual(verifier.targetTextDescription, "blue honda civic")
  }

  func test_init_setsTargetClasses() {
    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetClasses: ["car", "truck"],
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    XCTAssertEqual(verifier.targetClasses, ["car", "truck"])
  }

  func test_init_defaultTargetClasses() {
    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    XCTAssertEqual(verifier.targetClasses, ["car"])
  }

  // MARK: - Blur Detection

  func test_verify_rejectsBlurryImage() {
    let expectation = XCTestExpectation(description: "Verify completes")

    mockImageUtils.mockBlurScore = 0.5  // High blur score = blurry

    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    let image = createTestImage()
    let candidateId = UUID()

    verifier.verify(image: image, candidateId: candidateId)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          XCTAssertFalse(outcome.isMatch)
          XCTAssertEqual(outcome.rejectReason, .unclearImage)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 2.0)
  }

  func test_verify_passesSharpImage() {
    let expectation = XCTestExpectation(description: "Verify completes")

    mockImageUtils.mockBlurScore = 0.02  // Low blur score = sharp
    mockURLSession.setJSONResponse(
      TestAPIResponses.trafficEyeSuccess,
      for: "trafficeye.ai/recognition"
    )
    mockURLSession.setJSONResponse(
      TestAPIResponses.openAIMatch,
      for: "api.openai.com/v1/chat/completions"
    )

    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda civic",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    let image = createTestImage()
    let candidateId = UUID()

    verifier.verify(image: image, candidateId: candidateId)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          // Should proceed to API call and get a match
          XCTAssertTrue(outcome.isMatch)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 2.0)
  }

  // MARK: - API Response Parsing
  // Note: Tests that require chained TrafficEye + OpenAI API calls are better suited
  // for integration tests. The MockURLSession works for single-API tests but the
  // complex async chaining in TrafficEyeVerifier makes multi-API mocking unreliable.
  // These tests verify the simpler paths that don't require LLM comparison.

  func test_verify_handlesNoVehicleDetected() {
    let expectation = XCTestExpectation(description: "Verify completes")

    mockURLSession.setJSONResponse(
      TestAPIResponses.trafficEyeNoVehicle,
      for: "trafficeye.ai/recognition"
    )

    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    let image = createTestImage()
    let candidateId = UUID()

    verifier.verify(image: image, candidateId: candidateId)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          XCTAssertFalse(outcome.isMatch)
          XCTAssertEqual(outcome.rejectReason, .apiError)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 2.0)
  }

  func test_verify_handlesLowConfidenceMMR() {
    let expectation = XCTestExpectation(description: "Verify completes")

    mockURLSession.setJSONResponse(
      TestAPIResponses.trafficEyeLowConfidence,
      for: "trafficeye.ai/recognition"
    )

    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    let image = createTestImage()
    let candidateId = UUID()

    verifier.verify(image: image, candidateId: candidateId)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          XCTAssertFalse(outcome.isMatch)
          XCTAssertEqual(outcome.rejectReason, .insufficientInfo)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 2.0)
  }

  // MARK: - Network Error Handling

  func test_verify_handlesNetworkError() {
    let expectation = XCTestExpectation(description: "Verify completes")

    mockURLSession.setResponse(
      .error(URLError(.notConnectedToInternet)),
      for: "trafficeye.ai/recognition"
    )

    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    let image = createTestImage()
    let candidateId = UUID()

    verifier.verify(image: image, candidateId: candidateId)
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { outcome in
          // Network errors are caught and converted to no-MMR response
          XCTAssertFalse(outcome.isMatch)
          expectation.fulfill()
        }
      )
      .store(in: &cancellables)

    wait(for: [expectation], timeout: 2.0)
  }

  // MARK: - Time Since Last Verification

  func test_timeSinceLastVerification_tracksTime() {
    let config = VerificationConfig(expectedPlate: nil)
    let verifier = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    // Initially should be very small (just created)
    let initialTime = verifier.timeSinceLastVerification()
    XCTAssertLessThan(initialTime, 1.0)
  }

  // MARK: - URL Session Injection

  func test_urlSessionInjection_usesProvidedSession() {
    let config = VerificationConfig(expectedPlate: nil)
    let _ = TrafficEyeVerifier(
      targetTextDescription: "blue honda",
      config: config,
      imgUtils: mockImageUtils,
      urlSession: mockURLSession,
      trafficEyeApiKey: "test-key",
      openAIApiKey: "test-key"
    )

    // Verify the mock session is used (no requests yet)
    XCTAssertTrue(mockURLSession.requestHistory.isEmpty)
  }

  // MARK: - Helpers

  private func createTestImage() -> UIImage {
    let size = CGSize(width: 100, height: 100)
    UIGraphicsBeginImageContext(size)
    UIColor.blue.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return image
  }
}
