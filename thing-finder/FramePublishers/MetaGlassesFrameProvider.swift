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
    // Clean up stream session
    Task { @MainActor [streamSession] in
      await streamSession?.stop()
    }
  }

  // MARK: - FrameProvider Methods

  func setupSession() {
    guard streamSession == nil else { return }

    // Must be called on MainActor for MWDATCamera
    Task { @MainActor in
      self.setupSessionOnMain()
    }
  }

  @MainActor
  private func setupSessionOnMain() {
    guard streamSession == nil else { return }

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
        switch state {
        case .streaming:
          self.isRunning = true
          MetaGlassesManager.shared.isStreamActive = true
          MetaGlassesManager.shared.streamStartFailed = false
        case .stopped, .paused:
          self.isRunning = false
          MetaGlassesManager.shared.isStreamActive = false
        case .waitingForDevice:
          MetaGlassesManager.shared.isStreamActive = false
        default:
          break
        }
      }
    }

    // Subscribe to errors
    errorListenerToken = streamSession?.errorPublisher.listen { _ in }
  }

  func start() {
    guard !isRunning, !isStarting else { return }
    isStarting = true

    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.isStarting = false }

      // Reset failure flag for fresh attempt
      MetaGlassesManager.shared.streamStartFailed = false

      // Ensure session is set up before starting
      if self.streamSession == nil {
        self.setupSessionOnMain()
      }

      // Wait briefly for devices to become available if needed
      var devices = Wearables.shared.devices
      if devices.isEmpty {
        try? await Task.sleep(nanoseconds: 500_000_000)
        devices = Wearables.shared.devices
      }

      if !devices.isEmpty {
        // Check and request permissions
        do {
          let permission = Permission.camera

          var needsRequest = false
          do {
            let status = try await Wearables.shared.checkPermissionStatus(permission)
            needsRequest = (status != .granted)
          } catch {
            needsRequest = true
          }

          if needsRequest {
            MetaGlassesManager.shared.isPermissionRequestInProgress = true
            let requestStatus = try await Wearables.shared.requestPermission(permission)
            MetaGlassesManager.shared.isPermissionRequestInProgress = false
            if requestStatus != .granted {
              MetaGlassesManager.shared.isStreamActive = false
              MetaGlassesManager.shared.streamStartFailed = true
              MetaGlassesManager.shared.errorMessage =
                "Camera permission required. Please grant access in Meta AI app."
              return
            }
          }
        } catch {
          MetaGlassesManager.shared.isPermissionRequestInProgress = false
          MetaGlassesManager.shared.isStreamActive = false
          MetaGlassesManager.shared.streamStartFailed = true
          MetaGlassesManager.shared.errorMessage =
            "Camera permission required. Please grant access in Meta AI app."
          return
        }
      } else {
        MetaGlassesManager.shared.isStreamActive = false
        MetaGlassesManager.shared.streamStartFailed = true
        return
      }

      // Start the session
      guard self.streamSession != nil else { return }
      await self.streamSession?.start()
    }
  }

  func stop() {
    guard isRunning || isStarting || streamSession != nil else { return }

    Task { @MainActor in
      await self.teardownSession()
    }
  }

  @MainActor
  private func teardownSession() async {
    await streamSession?.stop()

    // Clear listener tokens
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil

    // Clear session so a fresh one is created on next start
    streamSession = nil
    deviceSelector = nil

    isRunning = false
    MetaGlassesManager.shared.isStreamActive = false
  }

  // MARK: - Video Frame Handling

  private var frameCount = 0

  @MainActor
  private func handleVideoFrame(_ videoFrame: VideoFrame) {
    frameCount += 1

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
