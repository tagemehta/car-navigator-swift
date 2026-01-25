/// ImageUtilities
/// ----------------
/// A convenience collection of Vision/graphics helpers used across the pipeline.
///
/// Responsibilities:
/// * Convert between Vision’s **upright, normalised** rectangles and buffer-space
///   coordinates for arbitrary `CGImagePropertyOrientation`s.
/// * Generate unscaled pixel + view bounding boxes for consistent cropping.
/// * Provide a shared singleton (`ImageUtilities.shared`) to avoid scattering
///   CIContext and math logic.
///

import CoreMedia
import SwiftUI
import Vision

public class ImageUtilities {
  public static let shared = ImageUtilities()
  private var ciImageContext: CIContext = CIContext()

  // https://machinethink.net/blog/bounding-boxes/
  // Bounding boxes are relative to the warped scaleFilled box in 0-1 space
  // assuming .scaleFill/videoGravity=resizeAspectFill.

  func cgOrientation(for uiOrientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
    switch uiOrientation {
    case .portrait: return .right
    case .portraitUpsideDown: return .left
    case .landscapeLeft: return .down
    case .landscapeRight: return .up
    default: return .right
    }
  }

  // MARK: - Rectangle rotation helpers (normalized ↔︎ pixel)
  /**
   Returns a rectangle transformed from upright (Vision) coordinates **to the buffer’s
   coordinate system** when the rectangle is already expressed in *normalised* (0-1)
   space.
   */
  public func inverseRotation(_ r: CGRect, for o: CGImagePropertyOrientation) -> CGRect {
    // https://developer.apple.com/documentation/imageio/cgimagepropertyorientation
    // Converts a rectangle in an upright buffer to the image space buffer
    // If you needed to rotate the buffer right to be upright.
    // Then to go from a box that is upright to one in buffer space you go left
    switch o {
    case .up: return r
    case .down: return CGRect(x: 1 - r.maxX, y: 1 - r.maxY, width: r.width, height: r.height)

    case .left:
      return CGRect(
        x: r.minY,
        y: 1 - r.maxX,
        width: r.height,
        height: r.width)

    case .right:
      return CGRect(
        x: 1 - r.maxY,
        y: r.minX,
        width: r.height,
        height: r.width)

    case .upMirrored: return CGRect(x: 1 - r.maxX, y: r.minY, width: r.width, height: r.height)
    case .downMirrored: return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    case .leftMirrored:
      return CGRect(x: 1 - r.maxY, y: 1 - r.maxX, width: r.height, height: r.width)
    case .rightMirrored: return CGRect(x: r.minY, y: r.maxX, width: r.height, height: r.width)

    @unknown default: return r
    }
  }

  /**
   Pixel-aware variant of `inverseRotation(_:for:)`.

   - Parameters:
     - r: The rectangle specified in **pixel coordinates** relative to an *upright* image.
     - imageSize: Size of the pixel buffer (width × height in pixels).
     - o: Orientation that the *buffer* must be rotated **to become upright**
           (same meaning as when you call Vision).

   This performs the same logical remapping as the normalised version but uses the
   buffer width/height instead of the unit square so it can be applied directly to
   pixel-space rectangles (e.g. those you want to crop).
   */
  public func inverseRotation(
    _ r: CGRect, in imageSize: CGSize, for o: CGImagePropertyOrientation
  ) -> CGRect {
    let W = imageSize.width
    let H = imageSize.height

    switch o {
    case .up:  // no rotation
      return r

    case .down:  // 180°
      return CGRect(
        x: W - r.maxX,
        y: H - r.maxY,
        width: r.width,
        height: r.height)

    case .left:  // 90° CCW (buffer had to rotate left to be upright ⇒ we rotate right)
      return CGRect(
        x: r.minY,
        y: W - r.maxX,
        width: r.height,
        height: r.width)

    case .right:  // 90° CW
      return CGRect(
        x: H - r.maxY,
        y: r.minX,
        width: r.height,
        height: r.width)

    case .upMirrored:
      return CGRect(
        x: W - r.maxX,
        y: r.minY,
        width: r.width,
        height: r.height)
    case .downMirrored:
      return CGRect(
        x: r.minX,
        y: H - r.maxY,
        width: r.width,
        height: r.height)
    case .leftMirrored:
      return CGRect(
        x: H - r.maxY,
        y: W - r.maxX,
        width: r.height,
        height: r.width)
    case .rightMirrored:
      return CGRect(
        x: r.minY,
        y: r.maxX,
        width: r.height,
        height: r.width)
    @unknown default:
      return r
    }
  }

  /// Convenience wrapper: rotates a *pixel-space* rectangle from buffer → upright.
  public func rotation(_ r: CGRect, in imageSize: CGSize, for o: CGImagePropertyOrientation)
    -> CGRect
  {
    let inv = self.inverseOrientation(o)
    return self.inverseRotation(r, in: imageSize, for: inv)
  }

  public func rotation(_ r: CGRect, for o: CGImagePropertyOrientation) -> CGRect {
    let ori = self.inverseOrientation(o)
    return self.inverseRotation(r, for: ori)
  }

  /// Converts a Vision **normalised, upright** bounding box into both buffer-pixel
  /// coordinates and view-space coordinates **without** introducing additional
  /// scaling distortion.
  ///
  /// Vision gives bounding boxes in an upright, unit-square coordinate system
  /// (origin is top-left, values 0–1).  In a typical camera preview you have:
  /// 1. A pixel buffer that may be rotated relative to upright.
  /// 2. A `UIView` (or CALayer) that displays the buffer with `AVLayerVideoGravity.resizeAspectFill`,
  ///    meaning portions of the buffer are cropped.
  ///
  /// This helper maps the rectangle through both coordinate spaces in one shot:
  /// * **imageRect** – pixel coordinates in *buffer orientation* (useful for cropping/embedding).
  /// * **viewRect**  – points in preview-layer space so overlays line up with the UI.
  ///
  /// - Parameters:
  ///   - normalizedRect: Bounding box from Vision (0–1, upright).
  ///   - imageSize: The buffer’s pixel dimensions (width × height).
  ///   - viewSize: Size of the preview view/layer after aspect-fill warping.
  ///   - orientation: Orientation the buffer must be rotated **to become upright** (same as provided to Vision).
  /// - Returns: A tuple `(imageRect, viewRect)` where:
  ///   - `imageRect` is in buffer pixel coordinates.
  ///   - `viewRect` is in preview-layer coordinates ready for CoreGraphics/SwiftUI drawing.
  func unscaledBoundingBoxes(
    for normalizedRect: CGRect,
    imageSize: CGSize,  // e.g. (width: CVPixelBufferGetWidth, height: CVPixelBufferGetHeight)
    viewSize: CGSize,  // e.g. videoPreview.bounds.size
    orientation: CGImagePropertyOrientation
  ) -> (imageRect: CGRect, viewRect: CGRect) {
    // -----------------------------------------------------------------------------------------
    // A. Vision outputs upright. Rotate back to buffer orientation (if buffer isn't upright)
    // -----------------------------------------------------------------------------------------
    let bufRectBL: CGRect
    let ori = orientation
    bufRectBL = self.inverseRotation(normalizedRect, for: ori)

    // ------------------------------------------------------------------
    // B. Flip to TOP-LEFT origin (what CoreGraphics & ARKit expect)
    // ------------------------------------------------------------------
    let bufRectTL = CGRect(
      x: bufRectBL.origin.x,
      y: 1 - bufRectBL.origin.y - bufRectBL.height,
      width: bufRectBL.width,
      height: bufRectBL.height)
    let uprightNormRectTL = CGRect(
      x: normalizedRect.origin.x,
      y: 1 - normalizedRect.origin.y - normalizedRect.height,
      width: normalizedRect.width,
      height: normalizedRect.height
    )

    // ------------------------------------------------------------------
    // C. IMAGE-SPACE RECT  (crop from CVPixelBuffer)
    // ------------------------------------------------------------------
    let imageRect = VNImageRectForNormalizedRect(
      bufRectTL, Int(imageSize.width), Int(imageSize.height))
    // ------------------------------------------------------------------
    // D. VIEW-SPACE RECT  (overlay)
    // ------------------------------------------------------------------

    var imageSizeRotated = imageSize
    switch ori {
    case .left, .right:
      imageSizeRotated = CGSize(width: imageSize.height, height: imageSize.width)
    default:
      break
    }
    let imageRectUpright = VNImageRectForNormalizedRect(
      uprightNormRectTL, Int(imageSizeRotated.width), Int(imageSizeRotated.height))
    // compute the uniform “fill” scale for image → view
    let scale = max(
      viewSize.width / imageSizeRotated.width,
      viewSize.height / imageSizeRotated.height
    )
    let scaledImageSize = CGSize(
      width: imageSizeRotated.width * scale,
      height: imageSizeRotated.height * scale
    )

    let xOffset = (viewSize.width - scaledImageSize.width) / 2
    let yOffset = (viewSize.height - scaledImageSize.height) / 2

    // 4) map image-pixel rect into view-pixel rect
    let viewX = imageRectUpright.minX * scale + xOffset
    let viewY = imageRectUpright.minY * scale + yOffset
    let viewW = imageRectUpright.width * scale
    let viewH = imageRectUpright.height * scale
    let viewRect = CGRect(x: viewX, y: viewY, width: viewW, height: viewH)

    return (imageRect, viewRect)
  }

  func inverseOrientation(_ ori: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
    switch ori {
    case .up: return .down
    case .down: return .up
    case .left: return .right
    case .right: return .left
    case .upMirrored: return .downMirrored
    case .downMirrored: return .upMirrored
    case .leftMirrored: return .rightMirrored
    case .rightMirrored: return .leftMirrored
    @unknown default: return ori
    }
  }

  func cvPixelBuffertoCGImage(buffer: CVPixelBuffer) -> CGImage {
    let ciImage = CIImage(cvPixelBuffer: buffer)
    return self.ciImageContext.createCGImage(ciImage, from: ciImage.extent)!
  }

  /// Returns a normalized blur score (0…1) for the given image using Core Image.
  /// - Parameter image: UIImage to analyze.
  /// - Returns: A Double blur score in [0,1], where 1 = maximally blurry and 0 = very sharp.
  func blurScore(from image: UIImage) -> Double? {
    guard let cgImage = image.cgImage else { return nil }

    let ciImage = CIImage(cgImage: cgImage)
    let context = CIContext(options: nil)

    guard let grayFilter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
    grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
    guard let grayImage = grayFilter.outputImage else { return nil }

    let weights: [CGFloat] = [
      -1, -1, -1,
      -1, 8, -1,
      -1, -1, -1,
    ]
    guard let lapFilter = CIFilter(name: "CIConvolution3X3") else { return nil }
    lapFilter.setValue(grayImage, forKey: kCIInputImageKey)
    lapFilter.setValue(CIVector(values: weights, count: 9), forKey: "inputWeights")
    lapFilter.setValue(0.0, forKey: "inputBias")
    guard let lapImage = lapFilter.outputImage else { return nil }

    guard let lapCG = context.createCGImage(lapImage, from: lapImage.extent) else { return nil }
    let width = lapCG.width
    let height = lapCG.height
    let bytesPerRow = width
    var pixelData = [UInt8](repeating: 0, count: width * height)
    let colorSpace = CGColorSpaceCreateDeviceGray()

    guard
      let bitmapCtx = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else { return nil }
    bitmapCtx.draw(lapCG, in: CGRect(x: 0, y: 0, width: width, height: height))

    var sum = 0.0
    var sumSq = 0.0
    let count = Double(pixelData.count)
    for v in pixelData {
      let dv = Double(v)
      sum += dv
      sumSq += dv * dv
    }
    let mean = sum / count
    let variance = sumSq / count - mean * mean

    let normalizedScore = 1.0 / (variance + 1.0)
    return min(max(normalizedScore, 0.0), 1.0)
  }
}

extension UIInterfaceOrientation {
  init(_ deviceOrientation: UIDeviceOrientation) {
    switch deviceOrientation {
    case .portrait: self = .portrait
    case .portraitUpsideDown: self = .portraitUpsideDown
    case .landscapeLeft: self = .landscapeRight
    case .landscapeRight: self = .landscapeLeft
    default: self = .portrait
    }
  }
}

extension UIImage.Orientation {
  init(_ cgOrientation: CGImagePropertyOrientation) {
    switch cgOrientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    }
  }
}
