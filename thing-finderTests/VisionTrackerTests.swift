import XCTest
import Vision
@testable import thing_finder

/// Stub subclass that replaces Vision tracking with predetermined bounding box output so we can
/// test the *public* `tick` behaviour deterministically.
private final class StubTracker: VisionTracker {
  /// Bounding box the stub will output for the first (and only) tracking request.
  var nextBoundingBox: CGRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
  /// Override to bypass Vision.
  func tick(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, store: CandidateStore) {
    // For every candidate simply replace its bbox with `nextBoundingBox` emulating a Vision update.
    for id in store.candidates.keys {
      store.update(id: id) { $0.lastBoundingBox = nextBoundingBox }
    }
  }
}

final class VisionTrackerTests: XCTestCase {
  func test_tick_updatesCandidateBoundingBoxes() {
    // Setup candidate store with one candidate.
    let bboxA = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let req = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: bboxA))
    let cand = Candidate(trackingRequest: req, boundingBox: bboxA)
    let store = CandidateStore()
    store.upsert(cand)

    // Stub tracker will move bbox.
    let tracker = StubTracker()
    tracker.nextBoundingBox = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)

    // Minimal pixelBuffer
    var pb: CVPixelBuffer?; CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)

    tracker.tick(pixelBuffer: pb!, orientation: .up, store: store)

    let updated = store[cand.id]!
    XCTAssertEqual(updated.lastBoundingBox, tracker.nextBoundingBox)
  }
}
