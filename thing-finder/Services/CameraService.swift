/*import Combine
import CoreImage
import Foundation
import SwiftUI
import Vision
import ARKit

/// Service that coordinates all camera-related functionality
class CameraService {
  // MARK: - Dependencies

  /// FPS calculator for frame rate management
  private let fpsCalculator: FPSCalculator

  /// Object tracker for tracking detected objects
  private let objectTracker: ObjectTracker
  private let visionTracker: VisionTrackingCoordinator

  /// Object detector for detecting objects in frames
  private let objectDetector: ObjectDetector

  /// Bounding box creator for creating bounding boxes
  private let boundingBoxCreator: BoundingBoxCreator

  /// Image utilities for image processing
  private let imgUtils: ImageUtilities
  /// Anchor tracking manager (ARKit flow)
  public let anchorManager: AnchorTrackingManager

  // MARK: - Initialization

  /// Initializes the camera service with all required dependencies
  /// - Parameters:
  ///   - fpsCalculator: FPS calculator for frame rate management
  ///   - objectTracker: Object tracker for tracking detected objects
  ///   - objectDetector: Object detector for detecting objects in frames
  ///   - boundingBoxCreator: Bounding box creator for creating bounding boxes
  ///   - imgUtils: Image utilities for image processing
  init(
    fpsCalculator: FPSCalculator,
    objectTracker: ObjectTracker,
    objectDetector: ObjectDetector,
    boundingBoxCreator: BoundingBoxCreator,
    imgUtils: ImageUtilities,
    anchorManager: AnchorTrackingManager,
    visionTracker: VisionTrackingCoordinator
  ) {
    self.fpsCalculator = fpsCalculator
    self.objectTracker = objectTracker
    self.objectDetector = objectDetector
    self.boundingBoxCreator = boundingBoxCreator
    self.imgUtils = imgUtils
    self.anchorManager = anchorManager
    self.visionTracker = visionTracker
  }

  // MARK: - ARKit Tracking Helpers
  func updateAnchors(with frame: ARFrame) {
    anchorManager.updateAnchors(from: frame)
  }
  func tryUpgradeCandidates(frame: ARFrame, session: ARSession) {
    anchorManager.attemptUpgradeCandidates(in: frame, session: session)
  }


  // MARK: - Public Methods

  /// Updates FPS calculation
  func updateFPSCalculation() {
    fpsCalculator.updateFPSCalculation()
  }

  /// Gets the current FPS
  var currentFPS: Double {
    return fpsCalculator.currentFPS
  }

  /// Gets the FPS publisher
  var fpsPublisher: AnyPublisher<Double, Never> {
    return fpsCalculator.fpsPublisher
  }


}
*/
