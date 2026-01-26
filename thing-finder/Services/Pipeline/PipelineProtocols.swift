//  PipelineProtocols.swift
//  thing-finder
//
//  Defines lightweight protocols for the per-frame pipeline services so that
//  the new `FramePipelineCoordinator` can be fully dependency-injected and unit
//  tests can replace any component with a mock.
//
//  These protocols deliberately avoid UIKit / SwiftUI so they build on macOS.

import CoreGraphics
import CoreMedia
import Foundation
import Vision

// MARK: - CaptureType

public enum CaptureSourceType {
  case avFoundation
  case arKit
  /// Playback from a local movie file via `VideoFileFrameProvider`.
  case videoFile
  /// Stream from Meta glasses (or MockDevice for testing).
  case metaGlasses
}

// MARK: - Object Detection

public protocol ObjectDetector {
  /// Run detection on the passed pixel buffer, returning abstract `Detection` objects.
  /// - Parameter filter: Optional closure to select relevant observations.
  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection]
}

// MARK: - Vision Tracking

public protocol VisionTracker {
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    store: CandidateStore
  )
}

// MARK: - Verification (LLM)

public protocol VerifierServiceProtocol {
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    store: CandidateStore
  )
}

// MARK: - Drift Repair

/// Protocol for drift repair services that re-associate candidates with detections
public protocol DriftRepairServiceProtocol {
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    detections: [Detection],
    store: CandidateStore
  )
}

// MARK: - EmbeddingProvider Protocol

/// Protocol for computing embeddings from image regions.
/// Allows injection of mock implementations for testing.
public protocol EmbeddingProvider {
  /// Computes an embedding for the specified region of an image.
  /// - Parameters:
  ///   - cgImage: The full image
  ///   - boundingBox: Normalized bounding box (0-1) specifying the region
  ///   - orientation: Image orientation
  /// - Returns: An embedding if computation succeeds, nil otherwise
  func computeEmbedding(
    from cgImage: CGImage,
    boundingBox: CGRect,
    orientation: CGImagePropertyOrientation
  ) -> (any EmbeddingProtocol)?
}

// MARK: - Depth Provider (ray-cast / LiDAR)

public protocol DepthProvider {
  /// Returns depth in meters for the given view-space point, or nil.
  func depth(at viewPoint: CGPoint) -> Double?
}

// MARK: - Navigation

public enum NavEvent {
  case start(targetClasses: [String], targetTextDescription: String)
  case searching
  case noMatch
  case lost
  case found
  case expired
}

public protocol NavigationManagerProtocol {
  func handle(_ event: NavEvent, box: CGRect?, distanceMeters: Double?)
  func announce(candidate: Candidate)
}
