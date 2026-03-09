/*
 * MetaGlassesFrameProvider.swift
 *
 * FrameProvider implementation for Meta glasses using the DAT SDK.
 * Uses MockDevice for testing without physical glasses.
 */

import CoreMedia
import MWDATCamera
import MWDATCore
import UIKit

#if DEBUG && canImport(MWDATMockDevice)
  import MWDATMockDevice
#endif

/// Configuration for the mock video source used when testing without physical glasses.
/// Change `mockVideoFileName` and `mockVideoFileExtension` to use a different video file.
enum MetaGlassesConfig {
  static let mockVideoFileName = "videoplayback.hevc"
  static let mockVideoFileExtension = "mp4"
}

final class MetaGlassesFrameProvider: NSObject, FrameProvider {

  // MARK: - FrameProvider Protocol

  let previewView: UIView = UIView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .metaGlasses
  private(set) var isRunning: Bool = false
  private var isStarting: Bool = false

  // MARK: - Meta DAT SDK

  private var streamSession: StreamSession?
  private var deviceSelector: AutoDeviceSelector?
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?

  // Preview layer for displaying video
  private let previewImageView: UIImageView = {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    return imageView
  }()

  // MARK: - Init

  override init() {
    super.init()
    previewView.addSubview(previewImageView)
    previewImageView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      previewImageView.topAnchor.constraint(equalTo: previewView.topAnchor),
      previewImageView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
      previewImageView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
      previewImageView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
    ])
  }

  deinit {
    // Note: Cannot call MainActor-isolated stop() from deinit
    // The streamSession will be cleaned up automatically
  }

  // MARK: - FrameProvider Methods

  func setupSession() {
    guard streamSession == nil else { return }

    // SDK requires MainActor - dispatch synchronously since we're likely already on main
    if Thread.isMainThread {
      MainActor.assumeIsolated {
        setupSessionOnMain()
      }
    } else {
      DispatchQueue.main.sync {
        MainActor.assumeIsolated { [self] in
          setupSessionOnMain()
        }
      }
    }
  }

  @MainActor
  private func setupSessionOnMain() {
    guard streamSession == nil else { return }

    print("[MetaGlassesFrameProvider] Setting up session...")
    print("[MetaGlassesFrameProvider] Registration state: \(Wearables.shared.registrationState)")
    print("[MetaGlassesFrameProvider] Current devices: \(Wearables.shared.devices)")

    let wearables = Wearables.shared
    deviceSelector = AutoDeviceSelector(wearables: wearables)

    let config = StreamSessionConfig(
      videoCodec: .raw,
      resolution: .low,
      frameRate: 24
    )

    guard let selector = deviceSelector else {
      print("[MetaGlassesFrameProvider] Failed to create device selector")
      return
    }
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: selector)
    print("[MetaGlassesFrameProvider] StreamSession created")

    // Subscribe to video frames
    videoFrameListenerToken = streamSession?.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.handleVideoFrame(videoFrame)
      }
    }

    // Subscribe to state changes
    stateListenerToken = streamSession?.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        guard let self else { return }
        print("[MetaGlassesFrameProvider] State changed: \(state)")
        switch state {
        case .streaming:
          self.isRunning = true
          MetaGlassesManager.shared.isStreamActive = true
          MetaGlassesManager.shared.streamStartFailed = false
        case .stopped, .paused:
          self.isRunning = false
          MetaGlassesManager.shared.isStreamActive = false
        case .waitingForDevice:
          // Glasses not available - signal fallback needed
          MetaGlassesManager.shared.isStreamActive = false
        default:
          break
        }
      }
    }

    // Subscribe to errors
    errorListenerToken = streamSession?.errorPublisher.listen { error in
      Task { @MainActor in
        print("[MetaGlassesFrameProvider] Stream error: \(error)")
      }
    }
  }

  func start() {
    guard !isRunning, !isStarting else { return }
    isStarting = true

    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.isStarting = false }
      // Check if we have any devices available
      let devices = Wearables.shared.devices
      print("[MetaGlassesFrameProvider] Available devices: \(devices)")

      if !devices.isEmpty {
        // Only check permissions if we have a real device
        do {
          let permission = Permission.camera
          let status = try await Wearables.shared.checkPermissionStatus(permission)
          print("[MetaGlassesFrameProvider] Permission status: \(status)")

          if status != .granted {
            print("[MetaGlassesFrameProvider] Permission not granted, requesting...")
            let requestStatus = try await Wearables.shared.requestPermission(permission)
            guard requestStatus == .granted else {
              print("[MetaGlassesFrameProvider] Camera permission denied after request")
              MetaGlassesManager.shared.isStreamActive = false
              return
            }
          }
        } catch {
          print("[MetaGlassesFrameProvider] Permission check/request failed: \(error)")
          // Permission failed - glasses can't stream, signal fallback
          MetaGlassesManager.shared.isStreamActive = false
          MetaGlassesManager.shared.streamStartFailed = true
          MetaGlassesManager.shared.errorMessage =
            "Camera permission required. Open Meta AI app to grant access."
          return
        }
      } else {
        print("[MetaGlassesFrameProvider] No devices available")
        MetaGlassesManager.shared.isStreamActive = false
        MetaGlassesManager.shared.streamStartFailed = true
        return
      }

      // Start the session - we have devices and permission
      await streamSession?.start()
      print("[MetaGlassesFrameProvider] Session started")
    }
  }

  func stop() {
    guard isRunning || isStarting || streamSession != nil else { return }

    Task { @MainActor in
      await streamSession?.stop()
      isRunning = false
      MetaGlassesManager.shared.isStreamActive = false
    }
  }

  // MARK: - Video Frame Handling

  private var frameCount = 0

  @MainActor
  private func handleVideoFrame(_ videoFrame: VideoFrame) {
    frameCount += 1
    if frameCount % 30 == 1 {
      print("[MetaGlassesFrameProvider] Received frame #\(frameCount)")
    }

    // Update preview
    if let uiImage = videoFrame.makeUIImage() {
      previewImageView.image = uiImage
    }

    // Convert to CVPixelBuffer and send to delegate
    let sampleBuffer = videoFrame.sampleBuffer
    if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      delegate?.processFrame(self, buffer: pixelBuffer, depthAt: { _ in nil })
    }
  }
}
