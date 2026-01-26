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

#if DEBUG
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

    let wearables = Wearables.shared
    deviceSelector = AutoDeviceSelector(wearables: wearables)

    let config = StreamSessionConfig(
      videoCodec: .raw,
      resolution: .low,
      frameRate: 24
    )

    guard let selector = deviceSelector else { return }
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
        print("[MetaGlassesFrameProvider] State changed: \(state)")
        switch state {
        case .streaming:
          self.isRunning = true
        case .stopped:
          self.isRunning = false
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
            let requestStatus = try await Wearables.shared.requestPermission(permission)
            guard requestStatus == .granted else {
              print("[MetaGlassesFrameProvider] Camera permission denied")
              return
            }
          }
        } catch {
          print("[MetaGlassesFrameProvider] Permission check failed: \(error)")
          // Continue anyway - AutoDeviceSelector will wait for device
        }
      } else {
        print("[MetaGlassesFrameProvider] No devices yet, starting session (will wait for device)")
      }

      // Start the session - AutoDeviceSelector will wait for a device if none available
      await streamSession?.start()
      print("[MetaGlassesFrameProvider] Session started")
    }
  }

  func stop() {
    guard isRunning else { return }

    Task { @MainActor in
      await streamSession?.stop()
      isRunning = false
    }
  }

  // MARK: - Video Frame Handling

  @MainActor
  private func handleVideoFrame(_ videoFrame: VideoFrame) {
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

// MARK: - Meta Glasses Manager (for Settings connection)

@MainActor
class MetaGlassesManager: ObservableObject {
  static let shared = MetaGlassesManager()

  @Published var isConfigured: Bool = false
  @Published var isRegistered: Bool = false
  @Published var availableDevices: [DeviceIdentifier] = []
  @Published var hasMockDevice: Bool = false
  @Published var errorMessage: String?

  private var registrationTask: Task<Void, Never>?
  private var deviceStreamTask: Task<Void, Never>?

  private init() {
    setupWearables()
  }

  private func setupWearables() {
    do {
      try Wearables.configure()
      isConfigured = true

      // Listen for registration state changes
      registrationTask = Task {
        for await state in Wearables.shared.registrationStateStream() {
          self.isRegistered = (state == .registered)
          if state == .registered {
            await self.setupDeviceStream()
          }
        }
      }
    } catch {
      errorMessage = "Failed to configure Wearables SDK: \(error)"
      print("[MetaGlassesManager] \(errorMessage!)")
    }
  }

  private func setupDeviceStream() async {
    deviceStreamTask?.cancel()
    deviceStreamTask = Task {
      for await devices in Wearables.shared.devicesStream() {
        self.availableDevices = devices
        #if DEBUG
          self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
      }
    }
  }

  func connectGlasses() {
    guard isConfigured else {
      errorMessage = "Wearables SDK not configured"
      return
    }
    guard Wearables.shared.registrationState != .registering else { return }

    do {
      try Wearables.shared.startRegistration()
    } catch {
      errorMessage = "Failed to start registration: \(error)"
    }
  }

  func disconnectGlasses() {
    do {
      try Wearables.shared.startUnregistration()
    } catch {
      errorMessage = "Failed to disconnect: \(error)"
    }
  }

  #if DEBUG
    func addMockDevice() {
      // Load video from bundle for mock streaming
      guard
        let videoURL = Bundle.main.url(
          forResource: MetaGlassesConfig.mockVideoFileName,
          withExtension: MetaGlassesConfig.mockVideoFileExtension)
      else {
        errorMessage =
          "Mock video file '\(MetaGlassesConfig.mockVideoFileName).\(MetaGlassesConfig.mockVideoFileExtension)' not found in bundle. Add it to the Xcode project."
        print("[MetaGlassesManager] \(errorMessage!)")
        return
      }

      print("[MetaGlassesManager] Found mock video at: \(videoURL)")

      // Create mock Ray-Ban Meta device (SDK is MainActor-isolated)
      // Priority inversion warnings are internal to the SDK and unavoidable
      let mockDevice = MockDeviceKit.shared.pairRaybanMeta()

      // Power on and unfold the device
      mockDevice.powerOn()
      mockDevice.unfold()

      // Set the camera feed from video file
      let cameraKit = mockDevice.getCameraKit()
      Task {
        await cameraKit.setCameraFeed(fileURL: videoURL)
        await MainActor.run { [weak self] in
          self?.hasMockDevice = true
        }
      }
    }

    func removeMockDevice() {
      for device in MockDeviceKit.shared.pairedDevices {
        MockDeviceKit.shared.unpairDevice(device)
      }
      hasMockDevice = false
    }
  #endif
}
