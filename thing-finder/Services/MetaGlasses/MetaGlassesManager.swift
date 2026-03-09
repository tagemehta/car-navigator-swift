//
//  MetaGlassesManager.swift
//  thing-finder
//
//  Singleton manager for Meta Ray-Ban glasses SDK lifecycle and connection state.
//

import Combine
import Foundation
import MWDATCore
import SwiftUI

#if DEBUG && canImport(MWDATMockDevice)
  import MWDATMockDevice
#endif

@MainActor
public final class MetaGlassesManager: ObservableObject {
  public static let shared = MetaGlassesManager()

  @Published public var isConfigured: Bool = false
  @Published public var isRegistered: Bool = false
  @Published public var availableDevices: [DeviceIdentifier] = []
  @Published public var hasMockDevice: Bool = false
  @Published public var errorMessage: String?
  @Published public var isRegistrationInProgress: Bool = false

  /// Tracks if registration was ever successful in this session (to handle SDK state flipping)
  @Published public var hasEverRegistered: Bool = false

  /// Set to true when registration completes via URL callback - triggers showing success modal
  @Published public var shouldShowRegistrationSuccess: Bool = false

  /// Tracks if the glasses stream is currently active and producing frames
  @Published public var isStreamActive: Bool = false

  /// Tracks if the stream failed to start (e.g., permission denied) - triggers fallback
  @Published public var streamStartFailed: Bool = false

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
          print("[MetaGlassesManager] Registration state: \(state)")
          self.isRegistered = (state == .registered)

          switch state {
          case .registered:
            // If we were in registration flow, show success modal
            if self.isRegistrationInProgress {
              self.shouldShowRegistrationSuccess = true
            }
            self.hasEverRegistered = true
            self.isRegistrationInProgress = false
            await self.setupDeviceStream()
            print("[MetaGlassesManager] isReadyForUse: \(self.isReadyForUse)")

          case .registering:
            self.isRegistrationInProgress = true

          default:
            // Any state other than registered/registering means unregistered
            self.hasEverRegistered = false
            self.isRegistrationInProgress = false
            self.isStreamActive = false
            self.streamStartFailed = false
            self.availableDevices = []
            self.deviceStreamTask?.cancel()
            self.deviceStreamTask = nil
            print("[MetaGlassesManager] State \(state) - state reset")
          }
        }
      }
    } catch {
      errorMessage = "Failed to configure Wearables SDK: \(error)"
      print("[MetaGlassesManager] \(errorMessage!)")
    }
  }

  private func setupDeviceStream() async {
    // Immediately check current devices
    self.availableDevices = Wearables.shared.devices
    print("[MetaGlassesManager] Initial devices: \(self.availableDevices)")

    deviceStreamTask?.cancel()
    deviceStreamTask = Task {
      for await devices in Wearables.shared.devicesStream() {
        self.availableDevices = devices
        print("[MetaGlassesManager] Devices updated: \(devices)")
        #if DEBUG && canImport(MWDATMockDevice)
          self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
      }
    }
  }

  public func connectGlasses() {
    errorMessage = nil
    guard isConfigured else {
      errorMessage = "Wearables SDK not configured"
      return
    }
    guard Wearables.shared.registrationState != .registering else { return }

    Task {
      do {
        try await Wearables.shared.startRegistration()
      } catch {
        self.errorMessage = "Failed to start registration: \(error)"
      }
    }
  }

  public func disconnectGlasses() {
    Task {
      do {
        try await Wearables.shared.startUnregistration()
      } catch {
        self.errorMessage = "Failed to disconnect: \(error)"
      }
    }
  }

  /// Returns true if glasses are registered and available for use
  public var isReadyForUse: Bool {
    return isRegistered && !availableDevices.isEmpty
  }

  #if DEBUG && canImport(MWDATMockDevice)
    public func addMockDevice() {
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

    public func removeMockDevice() {
      for device in MockDeviceKit.shared.pairedDevices {
        MockDeviceKit.shared.unpairDevice(device)
      }
      hasMockDevice = false
    }
  #endif
}
