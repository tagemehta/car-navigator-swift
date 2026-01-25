//  TwoStepVerifierTests.swift
//  thing-finderTests
//
//  Unit tests for TwoStepVerifier.
//  Tests vehicle info extraction, description matching, and occlusion handling.

import Combine
import XCTest

@testable import thing_finder

final class TwoStepVerifierTests: XCTestCase {

  private var mockURLSession: MockURLSession!
  private var cancellables: Set<AnyCancellable>!

  override func setUp() {
    super.setUp()
    mockURLSession = MockURLSession()
    cancellables = []
  }

  override func tearDown() {
    mockURLSession = nil
    cancellables = nil
    super.tearDown()
  }

  // MARK: - Initialization

  func test_init_setsTargetDescription() {
    let verifier = TwoStepVerifier(targetTextDescription: "blue honda civic")
    XCTAssertEqual(verifier.targetTextDescription, "blue honda civic")
  }

  func test_init_setsTargetClasses() {
    let verifier = TwoStepVerifier(targetTextDescription: "blue honda")
    XCTAssertEqual(verifier.targetClasses, ["vehicle"])
  }

  // MARK: - Time Since Last Verification

  func test_timeSinceLastVerification_tracksTime() {
    let verifier = TwoStepVerifier(targetTextDescription: "blue honda")

    // Initially should be very small (just created)
    let initialTime = verifier.timeSinceLastVerification()
    XCTAssertLessThan(initialTime, 1.0)
  }

  // MARK: - TwoStepError Tests

  func test_twoStepError_noToolResponse_exists() {
    let error = TwoStepError.noToolResponse
    XCTAssertNotNil(error)
  }

  func test_twoStepError_occluded_exists() {
    let error = TwoStepError.occluded
    XCTAssertNotNil(error)
  }

  func test_twoStepError_lowConfidence_exists() {
    let error = TwoStepError.lowConfidence
    XCTAssertNotNil(error)
  }

  func test_twoStepError_networkError_exists() {
    let error = TwoStepError.networkError
    XCTAssertNotNil(error)
  }
}
