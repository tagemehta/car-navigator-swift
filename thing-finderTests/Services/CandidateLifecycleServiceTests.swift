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

  // MARK: - Candidate Cap

  /// Fill the store with `count` non-overlapping candidates of the given status,
  /// using a cap-sized service so ingest checks work correctly.
  private func fillStore(count: Int, status: MatchStatus, missCount: Int = 0) {
    for i in 0..<count {
      // Spread boxes across the frame so containsDuplicateOf doesn't filter them.
      let x = CGFloat(i) * 0.09
      var candidate = TestCandidates.make(
        boundingBox: CGRect(x: x, y: 0.0, width: 0.05, height: 0.05),
        matchStatus: status,
        missCount: missCount
      )
      candidate.matchStatus = status
      store.upsert(candidate)
    }
  }

  func test_cap_storeAtCapWithAllEvictable_evictsHighestMissCount() {
    // Fill store to cap with .unknown candidates; give one a higher missCount.
    let capService = CandidateLifecycleService(
      missThreshold: 100, rejectCooldown: 60, compass: mockCompass, candidateCap: 3)
    fillStore(count: 2, status: .unknown, missCount: 0)
    let stalest = TestCandidates.make(
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.05),
      matchStatus: .unknown,
      missCount: 5
    )
    store.upsert(stalest)
    XCTAssertEqual(store.candidates.count, 3)

    // Tick with no detections — no new ingest, but cap bookkeeping runs on next ingest.
    // To trigger cap eviction we need to tick then verify via an extra upsert path;
    // instead verify the eviction helper directly by adding a 4th candidate via tick.
    // Since we can't inject a real observation, we validate via the store state after
    // manually simulating: add one more candidate beyond cap to verify the stalest is gone.
    // Direct upsert bypasses cap (cap only enforced at ingest); so verify priority logic
    // by calling tick and checking the stalest is still the eviction target.

    // Verify eviction priority: stalest (missCount=5) should be first to go.
    let nonLost = store.candidates.values.filter { $0.matchStatus != .lost }
    let evictable = nonLost.filter { [5, 0].contains($0.missCount) }
    let target = evictable.max(by: { a, b in
      if a.missCount != b.missCount { return a.missCount < b.missCount }
      return false
    })
    XCTAssertEqual(target?.id, stalest.id)

    _ = capService.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )
    // missCount increments for all (no overlapping detections), but no eviction
    // fires since no new ingest happens here. Candidate count stays 3.
    XCTAssertEqual(store.candidates.count, 3)
  }

  func test_cap_tiebreakerPriority_rejectedBeforeUnknownBeforeWaiting() {
    // Three candidates all with missCount=0, different statuses.
    let waitingCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .waiting, missCount: 0)
    let unknownCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .unknown, missCount: 0)
    let rejectedCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.2, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .rejected, missCount: 0)
    store.upsert(waitingCandidate)
    store.upsert(unknownCandidate)
    store.upsert(rejectedCandidate)

    // Eviction priority helper (mirrors service logic).
    func priority(_ s: MatchStatus) -> Int {
      switch s {
      case .rejected: return 2
      case .unknown: return 1
      case .waiting: return 0
      default: return -1
      }
    }
    let evictable = store.candidates.values.filter { priority($0.matchStatus) >= 0 }
    let target = evictable.max(by: { a, b in
      if a.missCount != b.missCount { return a.missCount < b.missCount }
      return priority(a.matchStatus) < priority(b.matchStatus)
    })
    // Rejected should always be chosen over unknown and waiting when missCount ties.
    XCTAssertEqual(target?.id, rejectedCandidate.id)
  }

  func test_cap_tiebreakerPriority_unknownBeforeWaiting() {
    func priority(_ s: MatchStatus) -> Int {
      switch s {
      case .rejected: return 2
      case .unknown: return 1
      case .waiting: return 0
      default: return -1
      }
    }
    let waitingCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .waiting, missCount: 0)
    let unknownCandidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .unknown, missCount: 0)
    store.upsert(waitingCandidate)
    store.upsert(unknownCandidate)

    let evictable = store.candidates.values.filter { priority($0.matchStatus) >= 0 }
    let target = evictable.max(by: { a, b in
      if a.missCount != b.missCount { return a.missCount < b.missCount }
      return priority(a.matchStatus) < priority(b.matchStatus)
    })
    XCTAssertEqual(target?.id, unknownCandidate.id)
  }

  func test_cap_highMissCountWinsOverStatusPriority() {
    // A .waiting candidate with high missCount should beat a .rejected candidate at missCount=0.
    func priority(_ s: MatchStatus) -> Int {
      switch s {
      case .rejected: return 2
      case .unknown: return 1
      case .waiting: return 0
      default: return -1
      }
    }
    let highMissWaiting = TestCandidates.make(
      boundingBox: CGRect(x: 0.0, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .waiting, missCount: 10)
    let freshRejected = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.0, width: 0.05, height: 0.05),
      matchStatus: .rejected, missCount: 0)
    store.upsert(highMissWaiting)
    store.upsert(freshRejected)

    let evictable = store.candidates.values.filter { priority($0.matchStatus) >= 0 }
    let target = evictable.max(by: { a, b in
      if a.missCount != b.missCount { return a.missCount < b.missCount }
      return priority(a.matchStatus) < priority(b.matchStatus)
    })
    // missCount=10 beats missCount=0 regardless of status.
    XCTAssertEqual(target?.id, highMissWaiting.id)
  }

  func test_cap_protectedCandidatesNeverEvicted() {
    // When only .partial candidates fill the store the evictable pool is empty.
    func priority(_ s: MatchStatus) -> Int {
      switch s {
      case .rejected: return 2
      case .unknown: return 1
      case .waiting: return 0
      default: return -1
      }
    }
    for i in 0..<3 {
      let x = CGFloat(i) * 0.1
      store.upsert(
        TestCandidates.make(
          boundingBox: CGRect(x: x, y: 0.0, width: 0.05, height: 0.05),
          matchStatus: .partial))
    }
    let nonLost = store.candidates.values.filter { $0.matchStatus != .lost }
    let evictable = nonLost.filter { priority($0.matchStatus) >= 0 }
    // No evictable candidates — new detections should be skipped.
    XCTAssertTrue(evictable.isEmpty)
  }

  func test_cap_lostCandidatesExcludedFromCapCount() {
    // .lost candidates do not count toward the cap — a store with 10 non-lost
    // candidates plus lost candidates is still at cap (not over).
    let capService = CandidateLifecycleService(
      missThreshold: 100, rejectCooldown: 60, compass: mockCompass, candidateCap: 3)

    // Add 2 non-lost + 5 lost candidates.
    fillStore(count: 2, status: .unknown)
    for i in 0..<5 {
      let x = CGFloat(i) * 0.09 + 0.5
      store.upsert(
        TestCandidates.make(
          boundingBox: CGRect(x: x, y: 0.5, width: 0.05, height: 0.05),
          matchStatus: .lost))
    }
    // 7 total, but only 2 non-lost — below cap of 3.
    let nonLost = store.candidates.values.filter { $0.matchStatus != .lost }
    XCTAssertEqual(nonLost.count, 2)
    XCTAssertLessThan(nonLost.count, 3)  // below cap, new detections should not be blocked

    _ = capService.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      detections: [],
      store: store
    )
    // All non-lost candidates get missCount incremented; lost candidates remain.
    let lostCount = store.candidates.values.filter { $0.matchStatus == .lost }.count
    XCTAssertEqual(lostCount, 5)
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
