import XCTest
import Vision
@testable import thing_finder

// MARK: - Helpers

private func makePixelBuffer() -> CVPixelBuffer {
  var pb: CVPixelBuffer?; CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)
  return pb!
}

private func makeDetection(box: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)) -> VNRecognizedObjectObservation {
  VNRecognizedObjectObservation(boundingBox: box)
}

// MARK: - Tests

final class CandidateLifecycleServiceTests: XCTestCase {
  private var service: CandidateLifecycleService!
  private var store: CandidateStore!

  override func setUp() {
    super.setUp()
    service = CandidateLifecycleService(imgUtils: ImageUtilities.shared, missThreshold: 15, rejectCooldown: 5)
    store = CandidateStore()
  }

  // 1. Ingest creates candidates
  func test_ingest_createsCandidates() {
    let detections = [makeDetection()]
    _ = service.tick(pixelBuffer: makePixelBuffer(), orientation: .up, imageSize: CGSize(width: 1, height: 1), detections: detections, store: store)
    XCTAssertEqual(store.candidates.count, 1)
  }

  // 2. Prune drops stale after missThreshold
  func test_prune_dropsStaleCandidates() {
    // First ingest
    let det = makeDetection()
    _ = service.tick(pixelBuffer: makePixelBuffer(), orientation: .up, imageSize: CGSize(width: 1, height: 1), detections: [det], store: store)
    XCTAssertEqual(store.candidates.count, 1)
    // Two frames with no detections -> missCount increments to 2 (threshold) -> candidate removed
    for _ in 0..<2 {
      _ = service.tick(pixelBuffer: makePixelBuffer(), orientation: .up, imageSize: CGSize(width: 1, height: 1), detections: [], store: store)
    }
    XCTAssertTrue(store.candidates.isEmpty)
  }

  // 3. allLost flag when matched candidate removed
  func test_allLost_trueWhenMatchedCandidateDropped() {
    // Ingest and mark matched
    let det = makeDetection()
    _ = service.tick(pixelBuffer: makePixelBuffer(), orientation: .up, imageSize: CGSize(width: 1, height: 1), detections: [det], store: store)
    guard let id = store.candidates.first?.key else { XCTFail(); return }
    store.update(id: id) { $0.matchStatus = .full }

    // Now two empty frames to drop it
    var lost = false
    for _ in 0..<2 {
      lost = service.tick(pixelBuffer: makePixelBuffer(), orientation: .up, imageSize: CGSize(width: 1, height: 1), detections: [], store: store)
    }
    XCTAssertTrue(lost)
    XCTAssertTrue(store.candidates.isEmpty)
  }
}
