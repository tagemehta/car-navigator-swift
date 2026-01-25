//  CandidateLifecycleServiceTests.swift
//  thing-finderTests
//
//  Unit tests for CandidateLifecycleService.
//  Tests lifecycle logic: missCount tracking, pruning, reject cooldown, compass updates,
//  and detection overlap handling using the Detection wrapper abstraction.

import CoreGraphics
import XCTest

@testable import thing_finder

final class CandidateLifecycleServiceTests: XCTestCase {

  private var store: CandidateStore!
  private var mockCompass: MockCompassProvider!
  private var service: CandidateLifecycleService!

  override func setUp() {
    super.setUp()
    store = CandidateStore()
    mockCompass = MockCompassProvider(degrees: 90.0)
    service = CandidateLifecycleService(
      missThreshold: 3,
      rejectCooldown: 1.0,
      compass: mockCompass
    )
  }

  override func tearDown() {
    store = nil
    mockCompass = nil
    service = nil
    super.tearDown()
  }

  // MARK: - Empty Store

  func test_tick_emptyStore_returnsNotLost() {
    let isLost = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    XCTAssertFalse(isLost)
    XCTAssertTrue(store.candidates.isEmpty)
  }

  // MARK: - MissCount Tracking

  func test_tick_noOverlappingDetection_incrementsMissCount() {
    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    store.upsert(candidate)

    // Tick with no detections - should increment missCount
    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    XCTAssertEqual(store[candidate.id]?.missCount, 1)
  }

  func test_tick_consecutiveMisses_incrementsMissCount() {
    // Use a service with higher threshold so candidate isn't removed
    let highThresholdService = CandidateLifecycleService(
      missThreshold: 10,
      rejectCooldown: 60.0,
      compass: mockCompass
    )

    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      missCount: 2
    )
    store.upsert(candidate)

    // Tick with no detections - missCount should increment
    _ = highThresholdService.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    XCTAssertEqual(store[candidate.id]?.missCount, 3)
  }

  func test_tick_missThresholdReached_removesUnmatchedCandidate() {
    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      matchStatus: .unknown,
      missCount: 2  // One more miss will reach threshold of 3
    )
    store.upsert(candidate)

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Candidate should be removed (not matched, exceeded threshold)
    XCTAssertNil(store[candidate.id])
  }

  func test_tick_missThresholdReached_matchedCandidate_marksAsLost() {
    let candidate = TestCandidates.makeMatched(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    var mutableCandidate = candidate
    mutableCandidate.missCount = 2  // One more miss will reach threshold
    store.upsert(mutableCandidate)

    let isLost = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Should return true (lost) and mark candidate as .lost instead of removing
    XCTAssertTrue(isLost)
    XCTAssertEqual(store[candidate.id]?.matchStatus, .lost)
  }

  // MARK: - Overlapping Detection Resets MissCount

  func test_tick_overlappingDetection_resetsMissCount() {
    let bbox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let candidate = TestCandidates.make(boundingBox: bbox, missCount: 2)
    store.upsert(candidate)

    // Create a detection that overlaps with the candidate
    let overlappingDetection = Detection(
      boundingBox: CGRect(x: 0.12, y: 0.12, width: 0.18, height: 0.18),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [overlappingDetection],
      store: store
    )

    // MissCount should be reset to 0 due to overlapping detection
    XCTAssertEqual(store[candidate.id]?.missCount, 0)
  }

  func test_tick_nonOverlappingDetection_incrementsMissCount() {
    let bbox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let candidate = TestCandidates.make(boundingBox: bbox, missCount: 1)
    store.upsert(candidate)

    // Create a detection that does NOT overlap with the candidate
    let nonOverlappingDetection = Detection(
      boundingBox: CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [nonOverlappingDetection],
      store: store
    )

    // MissCount should increment since detection doesn't overlap
    XCTAssertEqual(store[candidate.id]?.missCount, 2)
  }

  // MARK: - Compass Updates

  func test_tick_overlappingDetection_updatesCompassDegrees() {
    let bbox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let candidate = TestCandidates.make(boundingBox: bbox)
    store.upsert(candidate)
    mockCompass.degrees = 270.0

    // Create an overlapping detection to trigger compass update
    let overlappingDetection = Detection(
      boundingBox: CGRect(x: 0.12, y: 0.12, width: 0.18, height: 0.18),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [overlappingDetection],
      store: store
    )

    // Candidate's degrees should be updated from compass
    XCTAssertEqual(store[candidate.id]?.degrees, 270.0)
  }

  // MARK: - Reject Cooldown

  func test_tick_rejectedCandidate_removedAfterCooldown() {
    // Use high miss threshold so candidate isn't removed for misses
    let cooldownService = CandidateLifecycleService(
      missThreshold: 100,
      rejectCooldown: 1.0,
      compass: mockCompass
    )

    var candidate = TestCandidates.makeRejected(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    // Set lastUpdated to 2 seconds ago (cooldown is 1 second)
    candidate.lastUpdated = Date().addingTimeInterval(-2.0)
    store.upsert(candidate)

    _ = cooldownService.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Rejected candidate should be removed after cooldown
    XCTAssertNil(store[candidate.id])
  }

  func test_tick_rejectedCandidate_keptBeforeCooldown() {
    let candidate = TestCandidates.makeRejected(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    // Fresh candidate - lastUpdated is now
    store.upsert(candidate)

    // Use service with longer cooldown
    let longCooldownService = CandidateLifecycleService(
      missThreshold: 100,  // High threshold so it doesn't get removed for misses
      rejectCooldown: 60.0,
      compass: mockCompass
    )

    _ = longCooldownService.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Rejected candidate should still exist (cooldown not elapsed)
    XCTAssertNotNil(store[candidate.id])
  }

  // MARK: - Prune to Single Matched

  func test_tick_multipleMatchedCandidates_prunesAllButLatest() {
    let candidate1 = TestCandidates.makeMatched()
    var mutableCandidate1 = candidate1
    mutableCandidate1.lastUpdated = Date().addingTimeInterval(-10)
    store.upsert(mutableCandidate1)

    let candidate2 = TestCandidates.makeMatched()
    var mutableCandidate2 = candidate2
    mutableCandidate2.lastUpdated = Date()  // More recent
    store.upsert(mutableCandidate2)

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Only the most recent matched candidate should remain
    XCTAssertNil(store[candidate1.id])
    XCTAssertNotNil(store[candidate2.id])
  }

  // MARK: - Has Active Match Skips Ingestion

  func test_tick_hasActiveMatch_skipsIngestion() {
    // When there's an active match, new detections should not be ingested
    let matchedCandidate = TestCandidates.makeMatched()
    store.upsert(matchedCandidate)

    XCTAssertTrue(store.hasActiveMatch)

    // Even if we had detections, they wouldn't be ingested
    // (We can't test this fully without real VNRecognizedObjectObservation)
    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Store should still only have the one matched candidate
    XCTAssertEqual(store.candidates.count, 1)
  }

  // MARK: - Lost Candidates Stay in Store

  func test_tick_lostCandidate_staysInStore() {
    let candidate = TestCandidates.makeLost(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    var mutableCandidate = candidate
    mutableCandidate.missCount = 10  // Well above threshold
    store.upsert(mutableCandidate)

    _ = service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )

    // Lost candidates should stay in store (for potential recovery by DriftRepair)
    XCTAssertNotNil(store[candidate.id])
    XCTAssertEqual(store[candidate.id]?.matchStatus, .lost)
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
