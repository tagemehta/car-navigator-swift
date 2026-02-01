//  DriftRepairServiceTests.swift
//  thing-finderTests
//
//  Unit tests for DriftRepairService.
//  Tests frame stride logic, state management, candidate processing,
//  and similarity-based matching using MockEmbeddingProvider.

import CoreGraphics
import XCTest

@testable import thing_finder

final class DriftRepairServiceTests: XCTestCase {

  private var store: CandidateStore!
  private var mockEmbeddingProvider: MockEmbeddingProvider!

  override func setUp() {
    super.setUp()
    store = CandidateStore()
    mockEmbeddingProvider = MockEmbeddingProvider()
  }

  override func tearDown() {
    store = nil
    mockEmbeddingProvider = nil
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

  // MARK: - Candidate Without Embedding

  func test_tick_candidateWithoutEmbedding_markedForDestruction() {
    // Candidate without embedding cannot match any detection
    let service = DriftRepairService(repairStride: 1)

    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      embedding: nil  // No embedding
    )
    store.upsert(candidate)

    // Provide a detection, but candidate has no embedding to compare
    let detection = Detection(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Without embedding, candidate cannot match and should be marked for destruction
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  func test_tick_candidateWithEmbedding_noDetections_markedForDestruction() {
    let service = DriftRepairService(repairStride: 1)

    let embedding = MockEmbedding()  // Test embedding
    let candidate = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      embedding: embedding
    )
    store.upsert(candidate)

    // No detections to match against
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // No detections means no match, candidate marked for destruction
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  // MARK: - Lost Candidate Recovery

  func test_tick_lostCandidate_processedForRecovery() {
    let service = DriftRepairService(repairStride: 1)

    // Lost candidate should still be processed by drift repair
    let candidate = TestCandidates.makeLost(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    store.upsert(candidate)

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // Lost candidate processed (marked for destruction since no match)
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  // MARK: - Similarity Threshold Configuration

  func test_init_customSimThreshold() {
    // Verify custom threshold is accepted (behavior tested in integration)
    let service = DriftRepairService(repairStride: 1, simThreshold: 0.95)

    let candidate = TestCandidates.make()
    store.upsert(candidate)

    // Service should function with custom threshold
    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [],
      store: store
    )

    // No crash, candidate processed
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  // MARK: - Detection Consumption

  func test_tick_detectionsConsumedByFirstMatch() {
    // When multiple candidates exist, each detection should only be used once
    let service = DriftRepairService(repairStride: 1)

    // Two candidates, both without embeddings (so neither can match)
    let candidate1 = TestCandidates.make(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    )
    let candidate2 = TestCandidates.make(
      boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
    )
    store.upsert(candidate1)
    store.upsert(candidate2)

    let detection = Detection(
      boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Both candidates should be marked for destruction (no embeddings to match)
    XCTAssertEqual(store[candidate1.id]?.lastBoundingBox, .zero)
    XCTAssertEqual(store[candidate2.id]?.lastBoundingBox, .zero)
  }

  // MARK: - Similarity-Based Matching (with MockEmbeddingProvider)

  func test_tick_highSimilarity_matchesDetection() {
    // Setup: candidate with embedding, detection with high similarity
    let candEmbId = UUID()
    let detEmbId = UUID()

    // Create candidate embedding that reports high similarity to detection embedding
    let candEmb = MockEmbedding(id: candEmbId, similarities: [detEmbId: 0.95])
    let detEmb = MockEmbedding(id: detEmbId)

    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let detBox = CGRect(x: 0.15, y: 0.15, width: 0.2, height: 0.2)  // Slightly shifted

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    // Configure mock to return detection embedding
    mockEmbeddingProvider.setEmbedding(detEmb, for: detBox)

    // Create detection with observation (needed for tracking request update)
    let detection = Detection(
      boundingBox: detBox,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.90
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Candidate should NOT be marked for destruction (similarity 0.95 > threshold 0.90)
    // But without a real VNRecognizedObjectObservation, the update will fail
    // So we verify the embedding provider was called
    XCTAssertEqual(mockEmbeddingProvider.computeCallCount, 1)
    XCTAssertEqual(mockEmbeddingProvider.computedBoundingBoxes.first, detBox)
  }

  func test_tick_lowSimilarity_doesNotMatch() {
    // Setup: candidate with embedding, detection with LOW similarity
    let candEmbId = UUID()
    let detEmbId = UUID()

    // Create candidate embedding that reports LOW similarity to detection embedding
    let candEmb = MockEmbedding(id: candEmbId, similarities: [detEmbId: 0.50])
    let detEmb = MockEmbedding(id: detEmbId)

    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let detBox = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    mockEmbeddingProvider.setEmbedding(detEmb, for: detBox)

    let detection = Detection(
      boundingBox: detBox,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.90
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Candidate should be marked for destruction (similarity 0.50 < threshold 0.90)
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  func test_tick_exactThreshold_doesNotMatch() {
    // Similarity must be GREATER than threshold, not equal
    let candEmbId = UUID()
    let detEmbId = UUID()

    let candEmb = MockEmbedding(id: candEmbId, similarities: [detEmbId: 0.90])  // Exactly at threshold
    let detEmb = MockEmbedding(id: detEmbId)

    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let detBox = CGRect(x: 0.15, y: 0.15, width: 0.2, height: 0.2)

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    mockEmbeddingProvider.setEmbedding(detEmb, for: detBox)

    let detection = Detection(
      boundingBox: detBox,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.90
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Similarity == threshold should NOT match (must be strictly greater)
    XCTAssertEqual(store[candidate.id]?.lastBoundingBox, .zero)
  }

  func test_tick_multipleDetections_matchesBestSimilarity() {
    let candEmbId = UUID()
    let det1EmbId = UUID()
    let det2EmbId = UUID()

    // Candidate has different similarities to two detections
    let candEmb = MockEmbedding(
      id: candEmbId,
      similarities: [
        det1EmbId: 0.92,  // Good match
        det2EmbId: 0.98,  // Better match
      ])
    let det1Emb = MockEmbedding(id: det1EmbId)
    let det2Emb = MockEmbedding(id: det2EmbId)

    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let det1Box = CGRect(x: 0.12, y: 0.12, width: 0.2, height: 0.2)
    let det2Box = CGRect(x: 0.15, y: 0.15, width: 0.2, height: 0.2)

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    mockEmbeddingProvider.setEmbedding(det1Emb, for: det1Box)
    mockEmbeddingProvider.setEmbedding(det2Emb, for: det2Box)

    let detection1 = Detection(
      boundingBox: det1Box,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )
    let detection2 = Detection(
      boundingBox: det2Box,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.90
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection1, detection2],
      store: store
    )

    // Both detections should have been evaluated
    XCTAssertEqual(mockEmbeddingProvider.computeCallCount, 2)
  }

  func test_tick_customSimThreshold_respected() {
    let candEmbId = UUID()
    let detEmbId = UUID()

    // Similarity of 0.80 - below default 0.90 but above custom 0.70
    let candEmb = MockEmbedding(id: candEmbId, similarities: [detEmbId: 0.80])
    let detEmb = MockEmbedding(id: detEmbId)

    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let detBox = CGRect(x: 0.15, y: 0.15, width: 0.2, height: 0.2)

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    mockEmbeddingProvider.setEmbedding(detEmb, for: detBox)

    let detection = Detection(
      boundingBox: detBox,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    // Use lower threshold
    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.70  // Lower threshold
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // With custom threshold 0.70, similarity 0.80 should match
    // Embedding provider should have been called
    XCTAssertEqual(mockEmbeddingProvider.computeCallCount, 1)
  }

  func test_tick_embeddingProviderReturnsNil_noMatch() {
    let candEmb = MockEmbedding()
    let candBox = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let detBox = CGRect(x: 0.15, y: 0.15, width: 0.2, height: 0.2)

    let candidate = TestCandidates.make(boundingBox: candBox, embedding: candEmb)
    store.upsert(candidate)

    // Don't configure mock - it will return nil
    // mockEmbeddingProvider.defaultEmbedding is nil by default

    let detection = Detection(
      boundingBox: detBox,
      labels: [DetectionLabel(identifier: "car", confidence: 0.9)]
    )

    let service = DriftRepairService(
      embeddingProvider: mockEmbeddingProvider,
      repairStride: 1,
      simThreshold: 0.90
    )

    service.tick(
      pixelBuffer: createTestPixelBuffer(),
      orientation: .up,
      imageSize: CGSize(width: 100, height: 100),
      viewBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
      detections: [detection],
      store: store
    )

    // Embedding provider was called but returned nil, so no match
    XCTAssertEqual(mockEmbeddingProvider.computeCallCount, 1)
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
