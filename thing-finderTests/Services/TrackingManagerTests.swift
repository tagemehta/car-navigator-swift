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
    let wrapper = createTrackingRequestWrapper()
    tracker.addTracking(wrapper)

    XCTAssertTrue(tracker.hasActiveTracking)
  }

  func test_addTracking_multipleRequests_hasActiveTracking() {
    tracker.addTracking(createTrackingRequestWrapper())
    tracker.addTracking(createTrackingRequestWrapper())

    XCTAssertTrue(tracker.hasActiveTracking)
  }

  // MARK: - Clear Tracking

  func test_clearTracking_marksAllAsLastFrame() {
    let wrapper1 = createTrackingRequestWrapper()
    let wrapper2 = createTrackingRequestWrapper()
    tracker.addTracking(wrapper1)
    tracker.addTracking(wrapper2)

    tracker.clearTracking()

    // After clearing, isLastFrame should be true for all underlying Vision requests
    XCTAssertTrue(wrapper1.visionRequest!.isLastFrame)
    XCTAssertTrue(wrapper2.visionRequest!.isLastFrame)
  }

  func test_clearTrackingExcept_marksOthersAsLastFrame() {
    let keepWrapper = createTrackingRequestWrapper()
    let removeWrapper1 = createTrackingRequestWrapper()
    let removeWrapper2 = createTrackingRequestWrapper()
    tracker.addTracking(keepWrapper)
    tracker.addTracking(removeWrapper1)
    tracker.addTracking(removeWrapper2)

    tracker.clearTrackingExcept(keepWrapper.id)

    // Only the kept request should not be marked as last frame
    XCTAssertFalse(keepWrapper.visionRequest!.isLastFrame)
    XCTAssertTrue(removeWrapper1.visionRequest!.isLastFrame)
    XCTAssertTrue(removeWrapper2.visionRequest!.isLastFrame)
  }

  // MARK: - Create Tracking Request

  func test_createTrackingRequest_returnsValidWrapper() {
    let observation = createDetectedObjectObservation()
    let wrapper = tracker.createTrackingRequest(for: observation)

    // Verify wrapper was created with the observation
    XCTAssertNotNil(wrapper.visionRequest)
    XCTAssertNotNil(wrapper.visionRequest?.inputObservation)
  }

  func test_createTrackingRequest_usesProvidedObservation() {
    let boundingBox = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
    let observation = createDetectedObjectObservation(boundingBox: boundingBox)
    let wrapper = tracker.createTrackingRequest(for: observation)

    // The input observation should be set on the underlying request
    XCTAssertNotNil(wrapper.visionRequest?.inputObservation)
    XCTAssertEqual(wrapper.visionRequest?.inputObservation.boundingBox, boundingBox)
    // The wrapper should also have the bounding box
    XCTAssertEqual(wrapper.boundingBox, boundingBox)
  }

  // MARK: - TrackingRequest Wrapper Tests

  func test_trackingRequestWrapper_testInitDoesNotRequireVision() {
    // Test that we can create TrackingRequest without Vision for unit tests
    let wrapper = TrackingRequest(boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))

    XCTAssertNil(wrapper.visionRequest)
    XCTAssertEqual(wrapper.boundingBox, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    XCTAssertFalse(wrapper.isLastFrame)
  }

  func test_trackingRequestWrapper_equalityBasedOnId() {
    let id = UUID()
    let wrapper1 = TrackingRequest(id: id, boundingBox: .zero)
    let wrapper2 = TrackingRequest(id: id, boundingBox: CGRect(x: 1, y: 1, width: 1, height: 1))
    let wrapper3 = TrackingRequest(id: UUID(), boundingBox: .zero)

    // Same ID = equal
    XCTAssertEqual(wrapper1, wrapper2)
    // Different ID = not equal
    XCTAssertNotEqual(wrapper1, wrapper3)
  }

  // MARK: - Helpers

  private func createTrackingRequestWrapper() -> TrackingRequest {
    let observation = createDetectedObjectObservation()
    let visionRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
    return TrackingRequest(from: visionRequest)
  }

  private func createDetectedObjectObservation(
    boundingBox: CGRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
  ) -> VNDetectedObjectObservation {
    return VNDetectedObjectObservation(boundingBox: boundingBox)
  }
}
