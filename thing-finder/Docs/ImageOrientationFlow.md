# Image Orientation & Scaling Flow

This document describes how images are scaled, rotated, and transformed as they flow through the Vision framework and display pipeline.

## Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐     ┌──────────────┐
│  Frame Source   │ ──▶ │ Vision Framework │ ──▶ │ Bbox Transform  │ ──▶ │   Display    │
│  (CVPixelBuffer)│     │   (Detection)    │     │ (ImageUtilities)│     │  (SwiftUI)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘     └──────────────┘
```

## Frame Sources & Their Orientations

### AVFoundation (iPhone Camera)
- **Buffer orientation**: Landscape-left (sensor is physically rotated 90° CW)
- **Buffer dimensions**: e.g., 1920×1080 (width > height, landscape)
- **Orientation hint needed**: `.right` for portrait, `.up` for landscape-right
- **Preview rotation**: `AVCaptureVideoPreviewLayer` handles rotation via `videoRotationAngle`

### Meta Glasses
- **Buffer orientation**: Already upright (landscape, matching what user sees)
- **Buffer dimensions**: e.g., 1280×720 (width > height, landscape)
- **Orientation hint needed**: `.up` (no rotation needed)
- **Preview rotation**: None needed - image is already correctly oriented

### VideoFile (Test videos)
- **Buffer orientation**: Depends on video encoding
- **Handled by**: `VideoFileFrameProvider` with optional rotation via CIImage transforms

## Vision Framework Input

When calling `VNImageRequestHandler`, you provide:
1. `CVPixelBuffer` - the raw pixel data
2. `orientation: CGImagePropertyOrientation` - tells Vision how to rotate the buffer to make it upright

```swift
let handler = VNImageRequestHandler(
    cvPixelBuffer: imageBuffer,
    orientation: orientation,  // e.g., .right for portrait iPhone
    options: [:]
)
```

### Orientation Values (CGImagePropertyOrientation)

| Value   | Meaning                                      | Use Case                    |
|---------|----------------------------------------------|-----------------------------|
| `.up`   | Buffer is already upright                    | Meta glasses, landscape-right|
| `.down` | Buffer is rotated 180°                       | Upside-down                 |
| `.left` | Buffer needs 90° CCW rotation to be upright  | Portrait upside-down        |
| `.right`| Buffer needs 90° CW rotation to be upright   | Portrait (iPhone default)   |

## Vision Framework Output

Vision returns bounding boxes in **normalized, upright coordinates**:
- Origin: bottom-left (0,0)
- Range: 0.0 to 1.0
- Orientation: Always upright (as if the image were displayed correctly)

```swift
// Example: VNRecognizedObjectObservation.boundingBox
// CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
// This is in normalized, upright, bottom-left origin coordinates
```

## Coordinate Transformations (ImageUtilities.swift)

### 1. Vision → Buffer Space (`inverseRotation`)

Converts Vision's upright normalized rect back to buffer pixel coordinates:

```swift
// For portrait iPhone (orientation = .right):
// Vision rect (upright) → Buffer rect (rotated 90° CW)
let bufferRect = imgUtils.inverseRotation(visionRect, for: .right)
```

### 2. Bottom-Left → Top-Left Origin

CoreGraphics and UIKit use top-left origin, so we flip Y:

```swift
let topLeftRect = CGRect(
    x: bottomLeftRect.origin.x,
    y: 1 - bottomLeftRect.origin.y - bottomLeftRect.height,
    width: bottomLeftRect.width,
    height: bottomLeftRect.height
)
```

### 3. Normalized → Pixel Coordinates

```swift
let pixelRect = VNImageRectForNormalizedRect(
    normalizedRect,
    Int(bufferWidth),
    Int(bufferHeight)
)
```

### 4. Image → View Space (for overlay display)

Account for aspect-fill scaling and centering:

```swift
let scale = max(viewSize.width / imageSize.width, 
                viewSize.height / imageSize.height)
let viewRect = CGRect(
    x: imageRect.minX * scale + xOffset,
    y: imageRect.minY * scale + yOffset,
    width: imageRect.width * scale,
    height: imageRect.height * scale
)
```

## Current Flow in Code

### CameraViewModel.processFrame()
```swift
// 1. Get orientation based on device orientation
let orientation = ImageUtilities.shared.cgOrientation(for: interfaceOrientation)
// For portrait iPhone: returns .right

// 2. Pass to pipeline
pipeline.process(
    pixelBuffer: buffer,
    orientation: orientation,  // .right for portrait
    ...
)
```

### DetectionManager.detect()
```swift
// 3. Vision uses orientation to interpret buffer
let handler = VNImageRequestHandler(
    cvPixelBuffer: imageBuffer,
    orientation: orientation,  // .right
    options: [:]
)
// Vision internally rotates buffer 90° CW before detection
// Returns bounding boxes in upright coordinates
```

### ImageUtilities.unscaledBoundingBoxes()
```swift
// 4. Convert Vision bbox back to buffer coordinates for cropping
let bufRectBL = inverseRotation(normalizedRect, for: orientation)
// For .right: rotates rect 90° CCW (inverse of CW)

// 5. Flip to top-left origin
let bufRectTL = CGRect(x: bufRectBL.x, y: 1 - bufRectBL.maxY, ...)

// 6. Scale to pixels
let imageRect = VNImageRectForNormalizedRect(bufRectTL, width, height)

// 7. Scale to view for overlay
let viewRect = ... // aspect-fill math
```

## Meta Glasses Difference

**Key Issue**: Meta glasses provide buffers that are already upright (landscape orientation matching what the user sees). Unlike iPhone cameras, there's no 90° rotation needed.

### Current Problem
The code assumes all sources need the same orientation handling as AVFoundation:
```swift
let orientation = ImageUtilities.shared.cgOrientation(for: interfaceOrientation)
// Returns .right for portrait, but Meta glasses don't need this!
```

### Solution
For Meta glasses, always use `.up` orientation:
```swift
// In CameraViewModel or FramePipelineCoordinator:
let orientation: CGImagePropertyOrientation
switch captureType {
case .metaGlasses:
    orientation = .up  // Glasses frames are already upright
case .avFoundation, .arKit:
    orientation = imgUtils.cgOrientation(for: interfaceOrientation)
case .videoFile:
    // Depends on video encoding, may need configuration
    orientation = imgUtils.cgOrientation(for: interfaceOrientation)
}
```

## Summary Table

| Source        | Buffer Orientation | Vision Orientation | Preview Handling          |
|---------------|-------------------|-------------------|---------------------------|
| AVFoundation  | Landscape (90° CW)| `.right` (portrait)| AVCaptureVideoPreviewLayer|
| Meta Glasses  | Upright           | `.up`             | UIImageView (no rotation) |
| ARKit         | Upright           | `.up`             | ARSCNView                 |
| VideoFile     | Variable          | Configurable      | AVPlayerLayer + transform |

## Files Involved

- `ImageUtilities.swift` - Coordinate transforms
- `CameraViewModel.swift` - Orientation calculation, bbox mapping
- `FramePipelineCoordinator.swift` - Pipeline orchestration
- `DetectionManager.swift` - Vision request execution
- `TrackingManager.swift` - Vision tracking
- `VerifierService.swift` - Crop extraction for verification
- `VideoCapture.swift` - AVFoundation frame provider
- `MetaGlassesFrameProvider.swift` - Meta glasses frame provider
