//  CandidateStoreTests.swift
//  thing-finderTests
//
//  Unit tests for CandidateStore thread-safe collection.

import XCTest

@testable import thing_finder

final class CandidateStoreTests: XCTestCase {

  var store: CandidateStore!

  override func setUp() {
    super.setUp()
    store = CandidateStore()
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  // MARK: - Basic Operations

  func test_upsert_createsNewCandidate() {
    let candidate = TestCandidates.make()

    store.upsert(candidate)

    XCTAssertEqual(store.candidates.count, 1)
    XCTAssertNotNil(store[candidate.id])
    XCTAssertEqual(store[candidate.id]?.id, candidate.id)
  }

  func test_remove_deletesCandidate() {
    let candidate = TestCandidates.make()
    store.upsert(candidate)

    store.remove(id: candidate.id)

    XCTAssertEqual(store.candidates.count, 0)
    XCTAssertNil(store[candidate.id])
  }

  func test_update_mutatesCandidateInPlace() {
    let candidate = TestCandidates.make(matchStatus: .unknown)
    store.upsert(candidate)

    store.update(id: candidate.id) { cand in
      cand.matchStatus = .full
      cand.missCount = 5
    }

    XCTAssertEqual(store[candidate.id]?.matchStatus, .full)
    XCTAssertEqual(store[candidate.id]?.missCount, 5)
  }

  func test_update_setsLastUpdatedTimestamp() {
    let candidate = TestCandidates.make()
    store.upsert(candidate)
    let originalTime = store[candidate.id]?.lastUpdated

    // Small delay to ensure timestamp changes
    Thread.sleep(forTimeInterval: 0.01)

    store.update(id: candidate.id) { cand in
      cand.missCount += 1
    }

    let updatedTime = store[candidate.id]?.lastUpdated
    XCTAssertNotNil(updatedTime)
    XCTAssertGreaterThan(updatedTime!, originalTime!)
  }

  func test_update_nonExistentId_doesNothing() {
    let nonExistentId = UUID()

    // Should not crash
    store.update(id: nonExistentId) { cand in
      cand.missCount = 999
    }

    XCTAssertNil(store[nonExistentId])
  }

  func test_clear_removesAllCandidates() {
    store.upsert(TestCandidates.make())
    store.upsert(TestCandidates.make())
    store.upsert(TestCandidates.make())
    XCTAssertEqual(store.candidates.count, 3)

    store.clear()

    XCTAssertEqual(store.candidates.count, 0)
  }

  // MARK: - Snapshot

  func test_snapshot_returnsImmutableCopy() {
    let candidate = TestCandidates.make()
    store.upsert(candidate)

    let snapshot = store.snapshot()

    // Mutate store after snapshot
    store.update(id: candidate.id) { $0.missCount = 100 }

    // Snapshot should be unchanged
    XCTAssertEqual(snapshot[candidate.id]?.missCount, 0)
    // Store should be updated
    XCTAssertEqual(store[candidate.id]?.missCount, 100)
  }

  // MARK: - Duplicate Detection

  func test_containsDuplicateOf_highIoU_returnsTrue() {
    let bbox1 = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
    let candidate = TestCandidates.make(boundingBox: bbox1)
    store.upsert(candidate)

    // Overlapping box (high IoU)
    let bbox2 = CGRect(x: 0.22, y: 0.22, width: 0.4, height: 0.4)

    XCTAssertTrue(store.containsDuplicateOf(bbox2))
  }

  func test_containsDuplicateOf_noOverlap_returnsFalse() {
    let bbox1 = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
    let candidate = TestCandidates.make(boundingBox: bbox1)
    store.upsert(candidate)

    // Non-overlapping box
    let bbox2 = CGRect(x: 0.7, y: 0.7, width: 0.2, height: 0.2)

    XCTAssertFalse(store.containsDuplicateOf(bbox2))
  }

  func test_containsDuplicateOf_closeCenters_returnsTrue() {
    let bbox1 = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
    let candidate = TestCandidates.make(boundingBox: bbox1)
    store.upsert(candidate)

    // Different size but very close center
    let bbox2 = CGRect(x: 0.32, y: 0.32, width: 0.1, height: 0.1)

    XCTAssertTrue(store.containsDuplicateOf(bbox2))
  }

  func test_containsDuplicateOf_skipsLostCandidates() {
    let bbox = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
    let lostCandidate = TestCandidates.makeLost(boundingBox: bbox)
    store.upsert(lostCandidate)

    // Same bbox should NOT be considered duplicate since candidate is lost
    XCTAssertFalse(store.containsDuplicateOf(bbox))
  }

  // MARK: - hasActiveMatch

  func test_hasActiveMatch_detectsFull() {
    store.upsert(TestCandidates.make(matchStatus: .unknown))
    XCTAssertFalse(store.hasActiveMatch)

    store.upsert(TestCandidates.makeMatched())
    XCTAssertTrue(store.hasActiveMatch)
  }

  func test_hasActiveMatch_partialIsNotActive() {
    store.upsert(TestCandidates.make(matchStatus: .partial))
    XCTAssertFalse(store.hasActiveMatch)
  }

  // MARK: - pruneToSingleMatched

  func test_pruneToSingleMatched_keepsOnlyLatestMatched() {
    let older = TestCandidates.makeMatched()
    store.upsert(older)

    Thread.sleep(forTimeInterval: 0.01)

    let newer = TestCandidates.makeMatched()
    store.upsert(newer)

    // Update newer to ensure it has later lastUpdated
    store.update(id: newer.id) { _ in }

    store.pruneToSingleMatched()

    XCTAssertEqual(store.candidates.count, 1)
    XCTAssertNotNil(store[newer.id])
    XCTAssertNil(store[older.id])
  }

  func test_pruneToSingleMatched_noMatchedCandidates_keepsAll() {
    store.upsert(TestCandidates.make(matchStatus: .unknown))
    store.upsert(TestCandidates.make(matchStatus: .waiting))
    store.upsert(TestCandidates.make(matchStatus: .rejected))

    store.pruneToSingleMatched()

    XCTAssertEqual(store.candidates.count, 3)
  }

  // MARK: - Thread Safety

  func test_threadSafety_concurrentUpdates() {
    let expectation = expectation(description: "Concurrent updates complete")
    expectation.expectedFulfillmentCount = 100

    // Create initial candidates
    var ids: [CandidateID] = []
    for _ in 0..<10 {
      let candidate = TestCandidates.make()
      store.upsert(candidate)
      ids.append(candidate.id)
    }

    // Dispatch concurrent updates from background queues
    for i in 0..<100 {
      DispatchQueue.global(qos: .userInitiated).async {
        let id = ids[i % ids.count]
        self.store.update(id: id) { cand in
          cand.missCount += 1
        }
        expectation.fulfill()
      }
    }

    wait(for: [expectation], timeout: 5.0)

    // Verify no crashes occurred and data is consistent
    let totalMissCount = store.candidates.values.reduce(0) { $0 + $1.missCount }
    XCTAssertEqual(totalMissCount, 100)
  }

  // MARK: - Subscript

  func test_subscript_get_returnsCandidate() {
    let candidate = TestCandidates.make()
    store.upsert(candidate)

    XCTAssertNotNil(store[candidate.id])
    XCTAssertEqual(store[candidate.id]?.id, candidate.id)
  }

  func test_subscript_set_updatesCandidate() {
    var candidate = TestCandidates.make()
    store.upsert(candidate)

    candidate.missCount = 42
    store[candidate.id] = candidate

    XCTAssertEqual(store[candidate.id]?.missCount, 42)
  }

  func test_subscript_setNil_removesCandidate() {
    let candidate = TestCandidates.make()
    store.upsert(candidate)

    store[candidate.id] = nil

    XCTAssertNil(store[candidate.id])
    XCTAssertEqual(store.candidates.count, 0)
  }
}
