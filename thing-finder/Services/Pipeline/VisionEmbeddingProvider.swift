//  VisionEmbeddingProvider.swift
//  thing-finder
//
//  Production implementation of EmbeddingProvider using Vision framework.
//  Computes feature-print embeddings from image regions.

import CoreGraphics
import Vision

/// Production embedding provider that uses Vision's VNGenerateImageFeaturePrintRequest.
public final class VisionEmbeddingProvider: EmbeddingProvider {

  private let imageUtils: ImageUtilities

  public init(imageUtils: ImageUtilities = .shared) {
    self.imageUtils = imageUtils
  }

  public func computeEmbedding(
    from cgImage: CGImage,
    boundingBox: CGRect,
    orientation: CGImagePropertyOrientation
  ) -> Embedding? {
    let W = cgImage.width
    let H = cgImage.height
    let (imageRect, _) = imageUtils.unscaledBoundingBoxes(
      for: boundingBox,
      imageSize: CGSize(width: W, height: H),
      viewSize: CGSize(width: W, height: H),
      orientation: orientation
    )

    guard let crop = cgImage.cropping(to: imageRect) else { return nil }

    let handler = VNImageRequestHandler(cgImage: crop, options: [:])
    let request = VNGenerateImageFeaturePrintRequest()

    do {
      try handler.perform([request])
      guard let featurePrint = request.results?.first as? VNFeaturePrintObservation else {
        return nil
      }
      return Embedding(from: featurePrint)
    } catch {
      return nil
    }
  }
}
