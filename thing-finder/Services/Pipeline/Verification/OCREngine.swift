import CoreGraphics

/// Protocol to abstract OCR so `VerifierService` can be tested without Vision.
public protocol OCREngine {
  /// Attempts to recognize license-plate text from the cropped image.
  /// - Returns: nil when nothing recognizable; otherwise a result containing recognized text and confidence in `[0,1]`.
  func recognize(crop: CGImage) -> OCRResult?
}

public struct OCRResult {
  public let text: String
  public let confidence: Double
  public init(text: String, confidence: Double) {
    self.text = text
    self.confidence = confidence
  }
}
