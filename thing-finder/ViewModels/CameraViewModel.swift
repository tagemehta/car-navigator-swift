import Combine
import CoreGraphics
import SwiftUI
import Vision

/// A view model that manages the camera feed, object detection, and user interface updates.
///
/// This class coordinates between the camera feed, object detection services, and the UI.
/// It handles frame processing, object tracking, and state management while ensuring
/// thread safety and memory efficiency.
///
class CameraViewModel: NSObject, ObservableObject, FrameProviderDelegate {

  // MARK: - Dependencies

  private let dependencies: CameraDependencies
  // New coordinator-driven pipeline
  private let pipeline: FramePipelineCoordinator

  // MARK: - Published Properties

  /// Bounding boxes to display in the UI
  @Published var boundingBoxes: [BoundingBox] = []

  /// Current FPS value
  @Published private(set) var currentFPS: Double = 0.0

  // MARK: - Private Properties

  /// Interface orientation
  private var interfaceOrientation: UIInterfaceOrientation = .portrait

  /// Colors for different object classes
  private var colors: [String: UIColor] = [:]

  /// Cached preview view bounds
  private var cachedPreviewViewBounds: CGRect?

  /// Cached buffer dimensions
  private var cachedBufferDims: CGSize?

  /// Current capture source type (for orientation handling)
  private var currentCaptureSourceType: CaptureSourceType = .avFoundation

  /// In-flight verification requests
  private var inflight: [UUID: AnyCancellable] = [:]

  /// Confidence filter threshold
  private let CONFIDENCE_FILTER: Float = 0.4

  /// Image utilities for image processing
  private var imgUtils: ImageUtilities { dependencies.imageUtils }

  private var fpsManager: FPSCalculator { dependencies.fpsManager }
  // MARK: - Initialization

  /// Initializes the CameraViewModel with required parameters
  /// - Parameter dependencies: Container for all required dependencies
  init(dependencies: CameraDependencies) {
    // Build new pipeline coordinator
    self.pipeline = AppContainer.shared.makePipeline(
      classes: dependencies.targetClasses, description: dependencies.targetTextDescription)
    self.dependencies = dependencies
    super.init()

    // Set up publishers
    setupPublishers()

    // Listen to coordinator presentation updates -> convert to UI bounding boxes
    pipeline.$presentation
      .receive(on: DispatchQueue.main)
      .sink { [weak self] (pres: FramePresentation?) in
        guard let self, let pres = pres,
          let viewBounds = self.cachedPreviewViewBounds,
          let imageSize = self.cachedBufferDims
        else { return }
        // Use correct orientation based on capture source type
        let orientation: CGImagePropertyOrientation
        switch self.currentCaptureSourceType {
        case .metaGlasses:
          orientation = .up  // Glasses frames are already upright
        case .avFoundation, .arKit, .videoFile:
          orientation = self.imgUtils.cgOrientation(for: self.interfaceOrientation)
        }
        self.boundingBoxes = pres.candidates.map { cand in
          // Map normalized bbox to view-space rect
          //            if cand.matchStatus == .lost
          //            {continue}
          let (imageRect, viewRect) = self.imgUtils.unscaledBoundingBoxes(
            for: cand.lastBoundingBox,
            imageSize: imageSize,
            viewSize: viewBounds.size,
            orientation: orientation
          )
          let color: Color?
          switch cand.matchStatus {
          case .unknown: color = .yellow
          case .waiting: color = .blue
          case .full: color = .green
          case .partial: color = .orange
          case .rejected: color = .red
          case .lost: color = .black
          }
          return BoundingBox(
            imageRect: imageRect, viewRect: viewRect, label: cand.id.uuidString, color: color!)
        }
      }
      .store(in: &cancellables)
  }

  /// Convenience initializer for backward compatibility
  convenience init(targetClasses: [String], targetTextDescription: String, settings: Settings) {
    self.init(
      dependencies: .makeDefault(
        targetClasses: targetClasses,
        targetTextDescription: targetTextDescription,
        settings: settings
      )
    )
  }

  /// Sets up publishers for FPS and detection state
  private func setupPublishers() {
    self.fpsManager.fpsPublisher
      .receive(on: DispatchQueue.main)
      .assign(to: &$currentFPS)

  }

  /// Cancellables for storing subscriptions
  private var cancellables = Set<AnyCancellable>()

  /// Clean up resources when the view model is deallocated
  deinit {
    // Operations on main actor must be dispatched asynchronously from a non-isolated context.
    self.cancelAllInflight()
  }

  // MARK: - Orientation Handling

  /// Handles device orientation changes
  /// Handles device orientation changes and updates the UI accordingly.
  ///
  /// This method should be called when the device orientation changes.
  /// It ensures that the camera feed and UI elements are properly oriented.
  func handleOrientationChange() {
    // Reset bufferDims and cachedPreviewViewBounds to nil so they will be recalculated on next frame
    cachedBufferDims = nil
    cachedPreviewViewBounds = nil
    let deviceOrientation = UIDevice.current.orientation
    switch deviceOrientation {
    case .portrait: interfaceOrientation = .portrait
    case .portraitUpsideDown: interfaceOrientation = .portraitUpsideDown
    case .landscapeLeft: interfaceOrientation = .landscapeRight  // Note: these are flipped
    case .landscapeRight: interfaceOrientation = .landscapeLeft  // Note: these are flipped
    default: return  // Ignore face up/down and unknown orientations
    }
  }

  // MARK: - Frame Processing

  /// Processes a frame from the camera
  /// - Parameters:
  ///   - capture: The frame provider
  ///   - buffer: The pixel buffer containing the current frame
  ///   - depthAt: Function to get depth at a specific point
  ///   - imageToViewRect: Function to convert image rectangles to view rectangles
  func processFrame(
    _ capture: any FrameProvider, buffer: CVPixelBuffer, depthAt: @escaping (CGPoint) -> Float?
  ) {
    // Update FPS calculation
    // Set up frame dimensions and preview view bounds
    setupFrameDimensions(buffer, capture)
    guard let bufferSize = cachedBufferDims, let previewViewBounds = cachedPreviewViewBounds else {
      return
    }
    fpsManager.updateFPSCalculation()

    // Track current capture source for bbox mapping
    currentCaptureSourceType = capture.sourceType

    // Determine orientation based on capture source type
    // Meta glasses frames are already upright (no rotation needed)
    // AVFoundation/ARKit frames need rotation based on device orientation
    let orientation: CGImagePropertyOrientation
    switch capture.sourceType {
    case .metaGlasses:
      // Glasses camera produces upright frames - no rotation needed
      orientation = .up
    case .avFoundation, .arKit, .videoFile:
      // Phone camera sensor is rotated 90° - needs orientation hint
      orientation = ImageUtilities.shared.cgOrientation(
        for: UIInterfaceOrientation(UIDevice.current.orientation))
    }

    // NEW: delegate heavy lifting to coordinator
    pipeline.process(
      pixelBuffer: buffer,
      orientation: orientation,
      imageSize: bufferSize,
      viewBounds: previewViewBounds,
      depthAt: depthAt,
      captureType: capture.sourceType
    )

    return  // Skip legacy path below
  }
  // MARK: - Helper Methods

  /// Sets up frame dimensions
  /// - Parameters:
  ///   - buffer: The pixel buffer
  ///   - capture: The frame provider
  private func setupFrameDimensions(_ buffer: CVPixelBuffer, _ capture: any FrameProvider) {
    // Cache buffer dimensions if needed
    if cachedBufferDims == nil {
      let width = CVPixelBufferGetWidth(buffer)
      let height = CVPixelBufferGetHeight(buffer)
      cachedBufferDims = CGSize(width: width, height: height)
    }

    // Cache preview view bounds if needed
    if cachedPreviewViewBounds == nil {
      if Thread.isMainThread {
        cachedPreviewViewBounds = capture.previewView.bounds
      } else {
        DispatchQueue.main.sync {
          cachedPreviewViewBounds = capture.previewView.bounds
        }
      }
    }
  }

  /// Updates the bounding boxes in the UI
  /// - Parameter newBoundingBoxes: The new bounding boxes to display
  private func updateBoundingBoxes(to newBoundingBoxes: [BoundingBox]) {
    DispatchQueue.main.async { [weak self] in
      self?.boundingBoxes = newBoundingBoxes
    }
  }

  // Removed clearActiveTracking method - now using ObjectTracker through cameraService

  /// Cancels all in-flight verification requests
  private func cancelAllInflight() {
    self.inflight.values.forEach { $0.cancel() }
    self.inflight.removeAll()
  }
}
