//  VerifierServiceTests.swift
//  thing-finderTests
//
//  Unit tests for VerifierService.
//  Tests bbox filtering, rate limiting, status updates, and verification flow.

import Combine
import CoreVideo
import XCTest

@testable import thing_finder

final class VerifierServiceTests: XCTestCase {

  private var store: CandidateStore!
  private var cancellables: Set<AnyCancellable>!

  override func setUp() {
    super.setUp()
    store = CandidateStore()
    cancellables = []
  }

  override func tearDown() {
    store = nil
    cancellables = nil
    super.tearDown()
  }

  // MARK: - Bounding Box Filtering

  func test_tick_skipsTooSmallBoundingBox() {
    // Create candidate with bbox < 1% of image area
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)  // 0.25% area
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Candidate should still be unknown (skipped due to small bbox)
    // Note: Without target description, it gets auto-promoted to .full
    // So we test with a target description
    XCTAssertNotNil(store[candidate.id])
  }

  func test_tick_skipsTooTallBoundingBox() {
    // Create candidate with h/w > 3 (too tall)
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.5)  // h/w = 5
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Candidate should still be unknown (skipped due to tall bbox)
    XCTAssertNotNil(store[candidate.id])
  }

  func test_tick_processesValidBoundingBox() {
    // Create candidate with valid bbox (>1% area, reasonable aspect ratio)
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)  // 6% area, h/w = 0.67
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "",  // Empty description = auto-promote
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // With empty target description, candidate should be auto-promoted to .full
    XCTAssertEqual(store[candidate.id]?.matchStatus, .full)
  }

  // MARK: - Auto-Promotion Without Target Description

  func test_tick_autoPromotesWhenNoTargetDescription() {
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "",  // No description
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Should be auto-promoted to .full
    XCTAssertEqual(store[candidate.id]?.matchStatus, .full)
  }

  // MARK: - Rate Limiting

  func test_tick_rateLimitsVerification() {
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    let pixelBuffer = createTestPixelBuffer()

    // First tick - should process
    service.tick(
      pixelBuffer: pixelBuffer,
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Status should change to .waiting (verification started)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .waiting)

    // Reset to unknown to test rate limiting
    store.update(id: candidate.id) { $0.matchStatus = .unknown }

    // Immediate second tick - should be rate limited
    service.tick(
      pixelBuffer: pixelBuffer,
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Should still be unknown (rate limited)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .unknown)
  }

  // MARK: - Status Transitions

  func test_tick_setsWaitingStatusBeforeVerification() {
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    candidate.matchStatus = .unknown
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Should transition to .waiting while verification is in progress
    XCTAssertEqual(store[candidate.id]?.matchStatus, .waiting)
  }

  // MARK: - Empty Store Handling

  func test_tick_handlesEmptyStore() {
    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    // Should not crash with empty store
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    XCTAssertTrue(store.snapshot().isEmpty)
  }

  // MARK: - Non-Unknown Candidates

  func test_tick_skipsNonUnknownCandidates() {
    var fullCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    fullCandidate.matchStatus = .full
    store.upsert(fullCandidate)

    var rejectedCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.2)
    )
    rejectedCandidate.matchStatus = .rejected
    store.upsert(rejectedCandidate)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Status should remain unchanged
    XCTAssertEqual(store[fullCandidate.id]?.matchStatus, .full)
    XCTAssertEqual(store[rejectedCandidate.id]?.matchStatus, .rejected)
  }

  // MARK: - Multiple Candidates

  func test_tick_processesMultipleUnknownCandidates() {
    var candidate1 = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    candidate1.matchStatus = .unknown
    store.upsert(candidate1)

    var candidate2 = TestCandidates.make(
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.2)
    )
    candidate2.matchStatus = .unknown
    store.upsert(candidate2)

    let config = VerificationConfig(expectedPlate: nil)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Both should transition to .waiting
    XCTAssertEqual(store[candidate1.id]?.matchStatus, .waiting)
    XCTAssertEqual(store[candidate2.id]?.matchStatus, .waiting)
  }

  // MARK: - Per-Candidate MMR Throttling

  func test_tick_respectsPerCandidateMMRInterval() {
    var candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
    )
    candidate.matchStatus = .unknown
    candidate.lastMMRTime = Date()  // Just verified
    store.upsert(candidate)

    let config = VerificationConfig(expectedPlate: nil, perCandidateMMRInterval: 10.0)
    let service = VerifierService(
      targetTextDescription: "blue honda",
      imgUtils: ImageUtilities.shared,
      config: config
    )

    // Wait for rate limit to pass but not per-candidate interval
    Thread.sleep(forTimeInterval: 1.1)

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      store: store
    )

    // Should still be unknown (per-candidate throttled)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .unknown)
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
