//  ARVideoCapture.swift
//  Drop-in replacement for VideoCapture, with depth closure API.
//  Requires iOS 14+ and ARKit.
//
//  Note: ARKit is currently used primarily for depth data (via raycasting on LiDAR devices).
//  Spatial audio and AR anchors are potential future enhancements but not currently implemented.
//  The ARKit integration provides the foundation if these features are needed later.

import ARKit
import CoreVideo
import RealityKit
import UIKit
import simd

protocol ARVideoCaptureDelegate: AnyObject {
  /// - imageBuffer: the live camera frame
  /// - depthData: a closure you can call with any point in view coords to get its depth (in meters).
  ///              On LiDAR devices this reads the sceneDepth map; otherwise it raycasts.
  func processFrame(
    _ capture: ARVideoCapture,
    frame: ARFrame,
    imageBuffer: CVPixelBuffer,
    depthData: @escaping (CGPoint) -> Float?)
}

class ARVideoCapture: NSObject, ARSessionDelegate, FrameProvider {

  var sourceType = CaptureSourceType.arKit

  // MARK: - Public Properties

  /// Indicates whether the AR session is running.
  public private(set) var isRunning: Bool = false

  // MARK: - Private Properties

  /// The AR session being used for capture
  private let arSession: ARSession

  /// The AR configuration being used
  private var arConfiguration: ARWorldTrackingConfiguration

  /// The AR view that displays the camera feed and AR content
  private let previewARView: ARView

  /// Public preview view that can be added to the view hierarchy
  public var previewView: UIView { previewARView }

  /// Delegate to receive frames + depth closure.
  public weak var delegate: FrameProviderDelegate?

  /// Only let one frame process at a time
  private var isProcessingFrame: Bool = false
  override init() {
    // Initialize AR configuration
    self.arConfiguration = ARWorldTrackingConfiguration()

    // Initialize AR session
    self.arSession = ARSession()

    // Initialize AR view
    self.previewARView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    super.init()

    // Set up the AR view with our session
    previewARView.session = arSession
    previewARView.session.delegate = self
  }

  deinit {
    previewARView.session.pause()
  }

  // MARK: - Session Management

  /// Call once to start camera+tracking.
  public func start() {
    guard !isRunning else {
      print("AR session already running")
      return
    }

    // Ensure session is configured
    if arConfiguration.planeDetection.isEmpty {
      setupSession()
    }

    // Run the session
    print("Starting AR session with configuration: \(arConfiguration)")
    arSession.run(arConfiguration, options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
    print("AR session started")
  }

  /// Call to stop session.
  public func stop() {
    print("Stopping AR session...")
    guard isRunning else {
      print("AR session already stopped")
      return
    }

    // Pause the session and reset tracking
    arSession.pause()

    // Reset the configuration to clear any existing anchors
    arConfiguration = ARWorldTrackingConfiguration()

    isRunning = false
    print("AR session stopped")
  }

  // MARK: - FrameProvider

  /// Configures the AR session with the desired settings.
  /// This can be called before `start()` to customize the session configuration.
  public func setupSession() {
    // Configure AR session
    arConfiguration.planeDetection = [.horizontal, .vertical]

    // Enable scene depth if available
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      arConfiguration.frameSemantics.insert(.sceneDepth)
    }

    // Set video format for optimal performance
    if let format = ARWorldTrackingConfiguration.supportedVideoFormats
      .filter({ $0.framesPerSecond == 30 })
      .first
    {
      arConfiguration.videoFormat = format
    }

    // Configure environment texturing if available
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      arConfiguration.environmentTexturing = .automatic
    }

    print("AR session configured with plane detection: \(arConfiguration.planeDetection)")
    if arConfiguration.frameSemantics.contains(.sceneDepth) {
      print("Scene depth is enabled")
    }
  }

  // MARK: ARSessionDelegate

  public func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard !isProcessingFrame else {
      return
    }

    isProcessingFrame = true
    defer { isProcessingFrame = false }

    let pixelBuffer = frame.capturedImage
    let cameraTransform = frame.camera.transform
    // Build our depth‐lookup closure
    let depthProvider: (CGPoint) -> Float? = {
      [weak previewARView, weak session] point in

      // Raycast

      if let query = previewARView?.makeRaycastQuery(
        from: point,
        allowing: .estimatedPlane,
        alignment: .any
      ),
        let result = session?.raycast(query).first
      {
        let camPos = cameraTransform.columns.3
        let hitPos = result.worldTransform.columns.3
        return simd_distance(camPos, hitPos)
      }

      return nil
    }

    delegate?.processFrame(
      self,
      buffer: pixelBuffer,
      depthAt: depthProvider
    )
  }
}
