import Vision
import CoreGraphics

/// Production OCR engine that uses Vision's text recognition.
public final class VisionOCREngine: OCREngine {
  public init() {}

  /// - Returns: `OCRResult` when Vision recognizes at least one string, otherwise `nil`.
  public func recognize(crop: CGImage) -> OCRResult? {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.1

    let handler = VNImageRequestHandler(cgImage: crop, options: [:])
    do {
      try handler.perform([request])
      guard
        let best = request.results?
          .first?.topCandidates(1).first
      else { return nil }
      let cleaned = best.string.uppercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
      return OCRResult(text: cleaned, confidence: Double(best.confidence))
    } catch {
      print("Vision OCR error: \(error)")
      return nil
    }
  }
}
