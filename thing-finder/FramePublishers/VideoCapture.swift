//  Ultralytics YOLO 🚀 - AGPL-3.0 License
//
//  Video Capture for Ultralytics YOLOv8 Preview on iOS
//  Part of the Ultralytics YOLO app, this file defines the VideoCapture class to interface with the device's camera,
//  facilitating real-time video capture and frame processing for YOLOv8 model previews.
//  Licensed under AGPL-3.0. For commercial use, refer to Ultralytics licensing: https://ultralytics.com/license
//  Access the source code: https://github.com/ultralytics/yolo-ios-app
//
//  This class encapsulates camera initialization, session management, and frame capture delegate callbacks.
//  It dynamically selects the best available camera device, configures video input and output, and manages
//  the capture session. It also provides methods to start and stop video capture and delivers captured frames
//  to a delegate implementing the VideoCaptureDelegate protocol.

import AVKit
import Combine
import CoreVideo
import SwiftUI
import UIKit

// Identifies the best available camera device based on user preferences and device capabilities.
func bestCaptureDevice() -> AVCaptureDevice {
  // Prioritize LiDAR depth camera for best depth quality
  if let lidarDevice = AVCaptureDevice.default(
    .builtInLiDARDepthCamera, for: .video, position: .back)
  {
    print("Selected LiDAR depth camera for enhanced depth sensing")
    return lidarDevice
  }

  // Fall back to other camera types if LiDAR unavailable
  let deviceTypes: [AVCaptureDevice.DeviceType] = [
    .builtInTripleCamera,
    .builtInDualWideCamera,
    .builtInDualCamera,
    .builtInWideAngleCamera,
  ]
  let discoverySession = AVCaptureDevice.DiscoverySession(
    deviceTypes: deviceTypes, mediaType: .video, position: .back)
  guard let selectedDevice = discoverySession.devices.first else {
    fatalError("Expected back camera device is not available.")
  }
  print("Selected camera device: \(selectedDevice.deviceType.rawValue)")
  return selectedDevice
}

class VideoCapture: NSObject, FrameProvider {
  // MARK: - FrameProvider Protocol Properties
  public var previewView: UIView { _previewView as UIView }
  private var _previewView: AVPreviewView
  public var sourceType: CaptureSourceType = .avFoundation

  // Rotation handling
  private(set) var videoRotationAngle: CGFloat = 0 {
    didSet {
      if videoRotationAngle != oldValue {
        // Notify preview view of rotation change
        _previewView.updateRotation(angle: videoRotationAngle)
      }
    }
  }
  public weak var delegate: FrameProviderDelegate?

  private let captureDevice: AVCaptureDevice
  private let captureSession: AVCaptureSession
  private let videoOutput = AVCaptureVideoDataOutput()
  /// Depth / disparity capture (LiDAR or dual-camera).
  private let depthOutput = AVCaptureDepthDataOutput()
  private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
  private var currentRotationAngle: CGFloat = 0
  /// Dedicated queue for camera operations to avoid blocking the main thread
  private let cameraQueue = DispatchQueue(label: "camera-queue", qos: .userInitiated)
  // Configures the camera and capture session with optional session presets.

  /// Indicates whether the capture session is running.
  public var isRunning: Bool {
    return captureSession.isRunning
  }

  // MARK: - Lifecycle

  deinit {
    NotificationCenter.default.removeObserver(self)
    if Thread.isMainThread {
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
    } else {
      DispatchQueue.main.async {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
      }
    }
  }

  // MARK: - Rotation Handling

  private func setupRotationObservation() {
    // Start device orientation monitoring
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()

    // Observe orientation changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )

    // Initial update
    updateOrientation()
  }

  @objc private func handleOrientationChange() {
    updateOrientation()
  }

  private func updateOrientation() {
    let orientation = UIDevice.current.orientation
    let angle: CGFloat
    switch orientation {
    case .portrait:
      angle = 90
    case .portraitUpsideDown:
      angle = 270
    case .landscapeLeft:
      angle = 0
    case .landscapeRight:
      angle = 180
    default:
      angle = 0
    }

    // Update preview view
    _previewView.updateRotation(angle: angle)
  }

  // MARK: - Public Methods

  /// Starts the video capture session.
  public func start() {
    print("Starting video capture session...")
    if !captureSession.isRunning {
      // Run on the dedicated camera queue to avoid UI unresponsiveness
      cameraQueue.async { [weak self] in
        self?.captureSession.startRunning()
      }
    }
  }

  // Stops the video capture session.
  public func stop() {
    if captureSession.isRunning {
      // Run on the dedicated camera queue to avoid UI unresponsiveness
      cameraQueue.async { [weak self] in
        self?.captureSession.stopRunning()
      }
    }
  }
  override init() {
    self.captureDevice = bestCaptureDevice()
    self.captureSession = AVCaptureSession()
    self._previewView = AVPreviewView(session: captureSession, device: captureDevice)
    super.init()

    // Set up rotation observation
    setupRotationObservation()
  }

  /// Perform all AVFoundation plumbing. Call once after construction
  public func setupSession() {
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .inputPriority

    // MARK: Inputs
    let videoInput = try! AVCaptureDeviceInput(device: captureDevice)
    if captureSession.canAddInput(videoInput) {
      captureSession.addInput(videoInput)
    }

    // MARK: Outputs
    videoOutput.alwaysDiscardsLateVideoFrames = true
    var outputs: [AVCaptureOutput] = []
    if captureSession.canAddOutput(videoOutput) {
      captureSession.addOutput(videoOutput)
      outputs.append(videoOutput)
    }

    // MARK: Device configuration
    // Configure format BEFORE adding depth output so the connection check
    // runs against the correct active format.
    var depthConfigured = false
    do {
      try captureDevice.lockForConfiguration()
      captureDevice.focusMode = .continuousAutoFocus
      captureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
      captureDevice.exposureMode = .continuousAutoExposure

      // Configure depth format for best depth data quality
      // Find formats that support depth data, sorted by video resolution (highest first)
      let depthFormats = captureDevice.formats
        .filter { !$0.supportedDepthDataFormats.isEmpty }
        .sorted { a, b in
          let aRes = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
          let bRes = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
          return Int(aRes.width) * Int(aRes.height) > Int(bRes.width) * Int(bRes.height)
        }

      if let bestFormat = depthFormats.first {
        // Select the best depth format (prefer DepthFloat32 > DepthFloat16)
        let depthFormat =
          bestFormat.supportedDepthDataFormats.first { format in
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat32
          } ?? bestFormat.supportedDepthDataFormats.first { format in
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
          } ?? bestFormat.supportedDepthDataFormats.first

        if let depthFormat = depthFormat {
          captureDevice.activeFormat = bestFormat
          captureDevice.activeDepthDataFormat = depthFormat
          depthConfigured = true

          let videoRes = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
          print("Selected video format: \(videoRes.width)x\(videoRes.height)")

          let depthType = depthFormat.formatDescription.mediaSubType.rawValue
          let depthTypeName: String
          switch depthType {
          case kCVPixelFormatType_DepthFloat32:
            depthTypeName = "DepthFloat32"
          case kCVPixelFormatType_DepthFloat16:
            depthTypeName = "DepthFloat16"
          case kCVPixelFormatType_DisparityFloat32:
            depthTypeName = "DisparityFloat32"
          case kCVPixelFormatType_DisparityFloat16:
            depthTypeName = "DisparityFloat16"
          default:
            depthTypeName = "Unknown(\(depthType))"
          }
          print("Configured depth format: \(depthTypeName)")
        }
      } else {
        print("Warning: No depth-capable formats found on this device")
      }

      // Set explicit frame rate to 30fps
      if captureDevice.activeFormat.videoSupportedFrameRateRanges.first != nil {
        // Find a suitable frame rate range that includes 30fps
        let desiredFrameRate = 30.0
        let availableRanges = captureDevice.activeFormat.videoSupportedFrameRateRanges

        // Find a range that supports our desired frame rate
        if availableRanges.first(where: {
          $0.minFrameRate <= desiredFrameRate && $0.maxFrameRate >= desiredFrameRate
        }) != nil {
          // Set the frame duration (1/fps)
          let frameDuration = CMTime(value: 1, timescale: CMTimeScale(desiredFrameRate))
          captureDevice.activeVideoMinFrameDuration = frameDuration
          captureDevice.activeVideoMaxFrameDuration = frameDuration
          print("Set camera frame rate to \(desiredFrameRate) fps")
        } else {
          print("Camera does not support 30fps, using default frame rate")
        }
      }

      captureDevice.unlockForConfiguration()
    } catch {
      fatalError("Unable to configure the capture device.")
    }

    // MARK: Depth output
    // Add depth output AFTER format configuration so the connection check
    // reflects the actual active depth format.
    if depthConfigured {
      if captureSession.canAddOutput(depthOutput) {
        depthOutput.isFilteringEnabled = true
        depthOutput.alwaysDiscardsLateDepthData = true
        captureSession.addOutput(depthOutput)
        if depthOutput.connection(with: .depthData) != nil {
          outputs.append(depthOutput)
        } else {
          print("Warning: Depth output added but no valid connection")
        }
      } else {
        print("Warning: cannot add depth output")
      }
    }

    captureSession.commitConfiguration()

    // MARK: Preview layer & rotation
    _previewView.setupSession()

    outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: outputs)
    outputSynchronizer?.setDelegate(self, queue: cameraQueue)
  }
}

// Extension to handle AVCaptureVideoDataOutputSampleBufferDelegate events.
// MARK: - AVCapture Delegates
extension VideoCapture: AVCaptureDataOutputSynchronizerDelegate {
  public func dataOutputSynchronizer(
    _ synchronizer: AVCaptureDataOutputSynchronizer,
    didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
  ) {
    // Retrieve the synchronized depth and sample buffer container objects.
    let syncedDepthData =
      synchronizedDataCollection.synchronizedData(for: depthOutput)
      as? AVCaptureSynchronizedDepthData
    let syncedVideoData =
      synchronizedDataCollection.synchronizedData(for: videoOutput)
      as? AVCaptureSynchronizedSampleBufferData

    guard let pixelBuffer = syncedVideoData?.sampleBuffer.imageBuffer else { return }
    let depthProvider: (CGPoint) -> Float? = { point in
      var distanceMeters: Float32? = nil
      if let depthData = syncedDepthData?.depthData {
        let depth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthBuf = depth.depthDataMap
        CVPixelBufferLockBaseAddress(depthBuf, .readOnly)
        let width = CVPixelBufferGetWidth(depthBuf)
        let height = CVPixelBufferGetHeight(depthBuf)
        let x = max(0, min(width - 1, Int(point.x * CGFloat(width))))
        let y = max(0, min(height - 1, Int(point.y * CGFloat(height))))
        let normalizedPoint = CGPoint(x: x, y: y)
        if let base = CVPixelBufferGetBaseAddress(depthBuf) {
          let rowBytes = CVPixelBufferGetBytesPerRow(depthBuf)
          let ptr = base.advanced(
            by: Int(normalizedPoint.y) * rowBytes + Int(normalizedPoint.x)
              * MemoryLayout<Float32>.size)
          let val = ptr.load(as: Float32.self)
          if val.isFinite && val > 0 {
            distanceMeters = val
          }
        }
        CVPixelBufferUnlockBaseAddress(depthBuf, .readOnly)
        return distanceMeters
      }
      return nil
    }
    // Package the captured data.
    delegate?.processFrame(
      self,
      buffer: pixelBuffer,
      depthAt: depthProvider
    )
  }

}

// MARK: - AVCapture Output Delegates
extension VideoCapture {
  // These delegate callbacks are required so that the outputs actually emit data. We simply
  // forward the buffers to the synchronizer via no-op implementations because we already
  // consume synchronized data in `dataOutputSynchronizer(_:didOutput:)`.
  public func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // Intentionally left blank
  }

  public func captureOutput(
    _ output: AVCaptureOutput, didOutput depthData: AVDepthData, timestamp: CMTime,
    connection: AVCaptureConnection
  ) {
    // Intentionally left blank
  }
}

// https://medium.com/@hunter-pearson/using-avfoundations-rotationcoordinator-to-rotate-media-views-0171c336d7f1
class AVPreviewView: UIView {
  // MARK: - Properties

  private let session: AVCaptureSession

  override class var layerClass: AnyClass {
    AVCaptureVideoPreviewLayer.self
  }

  private var videoPreviewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }

  init(session: AVCaptureSession, device: AVCaptureDevice) {
    self.session = session
    super.init(frame: .zero)

    videoPreviewLayer.session = session
    videoPreviewLayer.videoGravity = .resizeAspectFill
  }

  deinit {
    // No-op; balanced in VideoCapture
  }

  /// Call after the associated AVCaptureSession is fully configured.
  public func setupSession() {
    videoPreviewLayer.session = session
    videoPreviewLayer.videoGravity = .resizeAspectFill
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Rotation

  func updateRotation(angle: CGFloat) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self,
        let connection = self.videoPreviewLayer.connection,
        connection.isVideoRotationAngleSupported(angle)
      else {
        return
      }

      connection.videoRotationAngle = angle
      self.videoPreviewLayer.setNeedsLayout()
    }
  }
}
