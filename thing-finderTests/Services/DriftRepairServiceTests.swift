//  DriftRepairServiceTests.swift
//  thing-finderTests
//
//  Unit tests for DriftRepairService.
//  Tests the frame stride logic and basic state management.
//  Note: Full drift repair with embeddings requires Vision integration tests.

import CoreGraphics
import XCTest

@testable import thing_finder

final class DriftRepairServiceTests: XCTestCase {

  private var store: CandidateStore!

  override func setUp() {
    super.setUp()
    store = CandidateStore()
  }

  override func tearDown() {
    store = nil
    super.tearDown()
  }

  // MARK: - Frame Stride Behavior

  func test_tick_beforeStrideReached_doesNotModifyCandidates() {
    // repairStride=1 means tick runs every frame
    // repairStride=15 means tick only runs on frame 15, 30, etc.
    let service = DriftRepairService(repairStride: 15)

    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    store.upsert(candidate)
    let originalBox = candidate.lastBoundingBox

    // Tick 14 times (frames 1-14) - should not trigger repair
    for _ in 1..<15 {
      service.tick(
        pixelBuffer: createTestPixelBuffer(),
        orientation: .up,
        imageSize: CGSize(width: 100, height: 100),
        viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
        detections: [],
        store: store
      )
    }

    // Candidate should be unchanged (no repair ran)
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, originalBox)
  }

  func test_tick_atStrideMultiple_runsRepair() {
    // Use repairStride=1 so repair runs every frame
    let service = DriftRepairService(repairStride: 1)

    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    store.upsert(candidate)

    // Tick once with no detections - candidate should be marked for destruction
    // (lastBoundingBox set to .zero when no match found)
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // With no matching detections and no embedding, candidate bbox should be zeroed
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  func test_tick_emptyStore_returnsEarly() {
    let service = DriftRepairService(repairStride: 1)

    // Should not crash with empty store
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    XCTAssertTrue(store.candidates.isEmpty)
  }

  func test_tick_multipleCandidates_processesAll() {
    let service = DriftRepairService(repairStride: 1)

    let candidate1 = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    let candidate2 = TestCandidates.make(
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
    )
    store.upsert(candidate1)
    store.upsert(candidate2)

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // Both candidates should be processed (marked for destruction with no matches)
    XCTAssertEqual(store[candidate1.id]?.lastBoundingBox, .zero)
    XCTAssertEqual(store[candidate2.id]?.lastBoundingBox, .zero)
  }

  // MARK: - Configuration

  func test_init_defaultValues() {
    let service = DriftRepairService()
    // Default repairStride is 15, simThreshold is 0.90
    // We can't directly access private properties, but we can verify behavior

    let candidate = TestCandidates.make()
    store.upsert(candidate)
    let originalBox = candidate.lastBoundingBox

    // First tick should not trigger repair (frame 1, stride 15)
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // Candidate should be unchanged
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, originalBox)
  }

  func test_init_customRepairStride() {
    let service = DriftRepairService(repairStride: 2)

    let candidate = TestCandidates.make()
    store.upsert(candidate)
    let originalBox = candidate.lastBoundingBox

    // Frame 1 - should not trigger
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, originalBox)

    // Frame 2 - should trigger repair
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
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
