//  TrackingManagerTests.swift
//  thing-finderTests
//
//  Unit tests for TrackingManager.
//  Tests the request management logic (add, clear, clearExcept).
//  Note: Actual Vision tracking (tick) requires real pixel buffers and is
//  better suited for integration tests.

import CoreGraphics
import Vision
import XCTest

@testable import thing_finder

final class TrackingManagerTests: XCTestCase {

  private var tracker: TrackingManager!

  override func setUp() {
    super.setUp()
    tracker = TrackingManager()
  }

  override func tearDown() {
    tracker = nil
    super.tearDown()
  }

  // MARK: - Initial State

  func test_initialState_hasNoActiveTracking() {
    XCTAssertFalse(tracker.hasActiveTracking)
  }

  // MARK: - Add Tracking

  func test_addTracking_singleRequest_hasActiveTracking() {
    let request = createTrackingRequest()
    tracker.addTracking(request)

    XCTAssertTrue(tracker.hasActiveTracking)
  }

  func test_addTracking_multipleRequests_hasActiveTracking() {
    let requests = [createTrackingRequest(), createTrackingRequest()]
    tracker.addTracking(requests)

    XCTAssertTrue(tracker.hasActiveTracking)
  }

  func test_addTrackingRequest_legacyMethod_addsRequest() {
    let request = createTrackingRequest()
    tracker.addTrackingRequest(request)

    XCTAssertTrue(tracker.hasActiveTracking)
  }

  // MARK: - Clear Tracking

  func test_clearTracking_marksAllAsLastFrame() {
    let request1 = createTrackingRequest()
    let request2 = createTrackingRequest()
    tracker.addTracking([request1, request2])

    tracker.clearTracking()

    // After clearing, isLastFrame should be true for all requests
    XCTAssertTrue(request1.isLastFrame)
    XCTAssertTrue(request2.isLastFrame)
  }

  func test_clearTrackingExcept_marksOthersAsLastFrame() {
    let keepRequest = createTrackingRequest()
    let removeRequest1 = createTrackingRequest()
    let removeRequest2 = createTrackingRequest()
    tracker.addTracking([keepRequest, removeRequest1, removeRequest2])

    tracker.clearTrackingExcept(keepRequest)

    // Only the kept request should not be marked as last frame
    XCTAssertFalse(keepRequest.isLastFrame)
    XCTAssertTrue(removeRequest1.isLastFrame)
    XCTAssertTrue(removeRequest2.isLastFrame)
  }

  // MARK: - Create Tracking Request

  func test_createTrackingRequest_returnsValidRequest() {
    let observation = createDetectedObjectObservation()
    let request = tracker.createTrackingRequest(for: observation)

    // Verify request was created with the observation
    XCTAssertNotNil(request)
    XCTAssertNotNil(request.inputObservation)
  }

  func test_createTrackingRequest_usesProvidedObservation() {
    let boundingBox = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
    let observation = createDetectedObjectObservation(boundingBox: boundingBox)
    let request = tracker.createTrackingRequest(for: observation)

    // The input observation should be set on the request
    XCTAssertNotNil(request.inputObservation)
    XCTAssertEqual(request.inputObservation.boundingBox, boundingBox)
  }

  // MARK: - Helpers

  private func createTrackingRequest() -> VNTrackObjectRequest {
    let observation = createDetectedObjectObservation()
    return VNTrackObjectRequest(detectedObjectObservation: observation)
  }

  private func createDetectedObjectObservation(
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  ) -> VNDetectedObjectObservation {
    return VNDetectedObjectObservation(boundingBox: boundingBox)
  }
}
