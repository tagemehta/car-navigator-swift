//
//  ImageUtilities.swift
//  thing-finder
//
//  Created by Tage Mehta on 6/10/25.
//

import CoreMedia
import ARKit
import SwiftUI
import Vision

class ImageUtilities {
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

// Removed ScalingOptions enum in favor of direct orientation parameter

// MARK: - AR Utilities
extension ImageUtilities {
  /// Projects a world-space anchor into 2D view coordinates.
  /// Returns `nil` if the anchor is behind the camera.
  /// For phase-1 we draw a fixed 40×40 rect centred on the projection point.
  func project(anchor: ARAnchor, frame: ARFrame, viewBounds: CGRect) -> CGRect? {
    // World position of anchor
    let posWorld = SIMD4<Float>(anchor.transform.columns.3.x,
                                anchor.transform.columns.3.y,
                                anchor.transform.columns.3.z,
                                1)
    // Transform to camera space
    let cameraToWorld = frame.camera.transform
    let worldToCamera = cameraToWorld.inverse
    let posCamera = simd_mul(worldToCamera, posWorld)
    // Positive z in camera space is behind the camera; we want negative z (in front)
    if posCamera.z >= 0 { return nil }

    // 2-D projection
    let projected2D = frame.camera.projectPoint(SIMD3<Float>(posWorld.x, posWorld.y, posWorld.z),
                                               orientation: .portrait,
                                               viewportSize: viewBounds.size)

    let size: CGFloat = 40
    let rect = CGRect(x: CGFloat(projected2D.x) - size/2,
                      y: CGFloat(projected2D.y) - size/2,
                      width: size,
                      height: size)
    return rect
  }
}
