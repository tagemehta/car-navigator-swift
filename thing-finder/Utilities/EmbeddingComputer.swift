/// A thin wrapper around Vision’s feature-print API for computing image embeddings.
///
/// `EmbeddingComputer` offers two convenience helpers:
/// * `compute(cgImage:)` – computes a feature-print for the entire image.
/// * `compute(cgImage:boundingBox:orientation:imageSize:)` – crops using a Vision-style
///   normalised bounding box before computing the embedding.
///
/// The utility is intentionally *stateless* so it can be invoked from anywhere without
/// dependency injection. If future requirements demand caching or a different embedding
/// model, the enum can be swapped for a protocol-backed service without touching
/// call-sites.

import CoreGraphics
import CoreVideo
import Vision

public enum EmbeddingComputer {
  /// Computes a Vision feature-print embedding for an entire `CGImage`.
///
/// - Parameter cgImage: The image to embed.
/// - Returns: A `VNFeaturePrintObservation` on success; `nil` if Vision fails.
  public static func compute(cgImage: CGImage) -> VNFeaturePrintObservation? {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNGenerateImageFeaturePrintRequest()
    do {
      try handler.perform([request])
      return request.results?.first as? VNFeaturePrintObservation
    } catch {
      return nil
    }
  }

  /// Crops the supplied image to `boundingBox` before producing an embedding.
///
/// - Parameters:
///   - cgImage: Full image in *upright* orientation.
///   - boundingBox: Normalised Vision rectangle (origin top-left, 0-1).
///   - orientation: Orientation that the buffer must be rotated to be upright (same as passed to Vision).
///   - imgUtils: Helper used for coordinate transforms. Defaults to `.shared`.
///   - imageSize: Pixel dimensions of `cgImage`.
/// - Returns: The feature-print for the crop, or `nil` on failure.
  public static func compute(
    cgImage: CGImage,
    boundingBox: CGRect,  // normalised (0-1, Vision)
    orientation: CGImagePropertyOrientation,
    imgUtils: ImageUtilities = .shared,
    imageSize: CGSize
  ) -> VNFeaturePrintObservation? {
    let (imageRect, _) = imgUtils.unscaledBoundingBoxes(
      for: boundingBox,
      imageSize: imageSize,
      viewSize: imageSize, // wrong but doesn't matter because not using
      orientation: orientation
    )
    
    guard let crop = cgImage.cropping(to: imageRect) else { return nil }

    return compute(cgImage: crop)
  }
}
