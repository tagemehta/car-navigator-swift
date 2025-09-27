import XCTest
import Vision
import Combine
@testable import thing_finder

// MARK: - Helpers

final class ConstantMatchVerifier: ImageVerifier {
    var targetClasses: [String] = ["car"]
    var targetTextDescription: String = "desc"
  func verify(image: UIImage, candidateId: UUID) -> AnyPublisher<VerificationOutcome, Error> {
        Just(VerificationOutcome(isMatch: true, description: "desc", rejectReason: nil))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    func timeSinceLastVerification() -> TimeInterval { 100 }
}

final class MockOCREngine: OCREngine {
    enum Output {
        case none
        case recognized(String, Double)
    }
    var output: Output = .none
    func recognize(crop: CGImage) -> OCRResult? {
        switch output {
        case .none:
            return nil
        case .recognized(let txt, let conf):
            return OCRResult(text: txt, confidence: conf)
        }
    }
}

private func tinyPixelBuffer() -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pb)
    return pb!
}

private func makeCandidate() -> Candidate {
    let bbox = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
    let obs = VNDetectedObjectObservation(boundingBox: bbox)
    let req = VNTrackObjectRequest(detectedObjectObservation: obs)
    return Candidate(trackingRequest: req, boundingBox: bbox)
}

// MARK: - Tests

final class VerifierServiceOCRTests: XCTestCase {
    private var verifier = ConstantMatchVerifier()
    private var ocrMock = MockOCREngine()
    private var service: VerifierService!
    private var store: CandidateStore!
    private var cancellables: Set<AnyCancellable> = []

    private func makeService(maxRetries: Int = 2) {
        let cfg = VerificationConfig(expectedPlate: nil, maxOCRRetries: maxRetries, shouldRunOCR: true)
        service = VerifierService(verifier: verifier, imgUtils: ImageUtilities.shared, config: cfg, ocrEngine: ocrMock)
    }

    override func setUp() {
        super.setUp()
        store = CandidateStore()
        makeService()
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_OCRSuccess_promotesToFull() {
        ocrMock.output = .recognized("ABC123", 0.95)
        let cand = makeCandidate(); store.upsert(cand)
        let exp = expectation(description: "full")
        store.$candidates.sink { dict in
            if dict[cand.id]?.matchStatus == .full { exp.fulfill() }
        }.store(in: &cancellables)

        service.tick(pixelBuffer: tinyPixelBuffer(), orientation: .up, imageSize: .init(width:1,height:1), viewBounds: .init(x:0,y:0,width:1,height:1), store: store)
        wait(for: [exp], timeout: 1.0)
    }

    func test_OCR_staysPartialUntilMax() {
        makeService(maxRetries: 2)
        ocrMock.output = .none
        let cand = makeCandidate(); store.upsert(cand)
        service.tick(pixelBuffer: tinyPixelBuffer(), orientation: .up, imageSize: .init(width:1,height:1), viewBounds: .init(x:0,y:0,width:1,height:1), store: store)
        XCTAssertEqual(store[cand.id]?.matchStatus, .partial)
        service.tick(pixelBuffer: tinyPixelBuffer(), orientation: .up, imageSize: .init(width:1,height:1), viewBounds: .init(x:0,y:0,width:1,height:1), store: store)
        XCTAssertEqual(store[cand.id]?.matchStatus, .partial)
    }

    func test_OCR_rejectedAfterMaxRetries() {
        makeService(maxRetries: 1)
        ocrMock.output = .none
        let cand = makeCandidate(); store.upsert(cand)
        service.tick(pixelBuffer: tinyPixelBuffer(), orientation: .up, imageSize: .init(width:1,height:1), viewBounds: .init(x:0,y:0,width:1,height:1), store: store)
        DispatchQueue.main.async {
          XCTAssertEqual(self.store[cand.id]?.matchStatus, .rejected)
        }
    }
}
