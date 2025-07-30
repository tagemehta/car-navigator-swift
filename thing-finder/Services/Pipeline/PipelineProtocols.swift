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
import CoreGraphics
import Vision

// MARK: - CaptureType

public enum CaptureSourceType {
  case avFoundation
  case arKit
  /// Playback from a local movie file via `VideoFileFrameProvider`.
  case videoFile
}

// MARK: - Object Detection

public protocol ObjectDetector {
  /// Run detection on the passed pixel buffer, returning Vision observations.
  /// - Parameter filter: Optional closure to select relevant observations.
  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: (VNRecognizedObjectObservation) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [VNRecognizedObjectObservation]
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

public protocol DriftRepairServiceProtocol {
  func tick(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    detections: [VNRecognizedObjectObservation],
    store: CandidateStore
  )
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
