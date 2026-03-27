//
//  MetaGlassesManager.swift
//  thing-finder
//
//  Singleton manager for Meta Ray-Ban glasses SDK lifecycle and connection state.
//
//  Architecture: single `GlassesState` enum is the source of truth.
//  All published booleans are derived — never set independently.
//
//  State machine:
//    unconfigured → idle → registering → registered → requestingPermission → ready → streaming
//                                                                                  ↘ failed(reason)
//                   ↑____________________________↙  (on unregistration)
//

import Combine
import Foundation
import MWDATCamera
import MWDATCore
import SwiftUI

#if DEBUG && canImport(MWDATMockDevice)
  import MWDATMockDevice
#endif

// MARK: - State Machine

/// Every possible state the Meta glasses integration can be in.
/// Eliminates impossible state combinations that scattered booleans allow.
public enum GlassesState: Equatable {
  /// Wearables.configure() has not been called or failed.
  case unconfigured
  /// SDK configured but not registered with Meta AI.
  case idle
  /// Registration flow in progress (app may leave to Meta AI).
  case registering
  /// Registered with Meta AI, waiting for user to start streaming.
  case registered
  /// Camera permission request is in flight (app may leave to Meta AI).
  case requestingPermission
  /// Permission granted, ready to stream (or streaming hasn't started yet).
  case ready
  /// Actively streaming frames from glasses.
  case streaming
  /// A recoverable failure occurred; message explains why.
  case failed(String)
}

@MainActor
public final class MetaGlassesManager: ObservableObject {
  public static let shared = MetaGlassesManager()

  // MARK: - Single source of truth

  @Published public private(set) var state: GlassesState = .unconfigured

  // MARK: - Supplementary published state (not booleans about lifecycle)

  @Published public private(set) var availableDevices: [DeviceIdentifier] = []
  @Published public var hasMockDevice: Bool = false

  /// One-shot flag: set when registration completes via URL callback.
  /// Views observe this to show a success modal, then reset it.
  @Published public var shouldShowRegistrationSuccess: Bool = false

  // MARK: - Derived convenience (read-only)

  /// True when glasses are usable as a camera source (permission granted).
  public var isReady: Bool {
    switch state {
    case .ready, .streaming: return true
    default: return false
    }
  }

  /// True when the stream is actively producing frames.
  public var isStreaming: Bool { state == .streaming }

  /// True during flows that leave the app (registration or permission request).
  public var isAwaitingExternalFlow: Bool {
    switch state {
    case .registering, .requestingPermission: return true
    default: return false
    }
  }

  /// True when registered (or better) with Meta AI.
  public var isRegistered: Bool {
    switch state {
    case .registered, .requestingPermission, .ready, .streaming: return true
    default: return false
    }
  }

  /// Whether the capture source should fall back to the phone camera.
  /// True when in a failed state or not yet ready.
  public var shouldFallback: Bool {
    if case .failed = state { return true }
    return false
  }

  /// User-facing error message, derived from failed state.
  public var errorMessage: String? {
    if case .failed(let msg) = state { return msg }
    return nil
  }

  // MARK: - Private

  /// Tracks whether we came through the registration flow (vs. app relaunch with persisted state).
  private var didInitiateRegistration = false
  /// Persists camera permission grant across app launches so we don't re-request.
  /// Cleared on unregistration.
  @AppStorage("meta_glasses_permission_granted") var permissionGranted: Bool = false
  private var registrationTask: Task<Void, Never>?
  private var deviceStreamTask: Task<Void, Never>?

  // MARK: - Init

  private init() {
    configureSDK()
  }

  // MARK: - SDK Configuration

  private func configureSDK() {
    do {
      try Wearables.configure()
    } catch {
      state = .failed("Failed to configure Wearables SDK: \(error.localizedDescription)")
      return
    }

    // Check persisted registration state from a previous session
    let currentState = Wearables.shared.registrationState
    handleSDKRegistrationState(currentState, isInitial: true)

    // Listen for future registration state changes
    registrationTask = Task { [weak self] in
      guard let self else { return }
      for await sdkState in Wearables.shared.registrationStateStream() {
        self.handleSDKRegistrationState(sdkState, isInitial: false)
      }
    }
  }

  /// Maps SDK RegistrationState → our GlassesState.
  private func handleSDKRegistrationState(_ sdkState: RegistrationState, isInitial: Bool) {
    switch sdkState {
    case .registered:
      // If we actively initiated registration (not a relaunch), show success
      if didInitiateRegistration && !isInitial {
        shouldShowRegistrationSuccess = true
      }
      didInitiateRegistration = false
      availableDevices = Wearables.shared.devices
      // Move to registered; streaming will be started by the FrameProvider
      if permissionGranted {
        state = .ready
      } else {
        state = .registered
      }
      startDeviceStream()

    case .registering:
      state = .registering
    case .unavailable:
      resetToIdle(clearPermission: true)
    case .available:
      resetToIdle(clearPermission: false)
    @unknown default:
      resetToIdle(clearPermission: false)
    }
  }

  private func resetToIdle(clearPermission: Bool) {
    state = .idle
    if clearPermission {
      permissionGranted = false
    }
    didInitiateRegistration = false
    availableDevices = []
    deviceStreamTask?.cancel()
    deviceStreamTask = nil
  }

  // MARK: - Device Discovery

  private func startDeviceStream() {
    availableDevices = Wearables.shared.devices

    deviceStreamTask?.cancel()
    deviceStreamTask = Task { [weak self] in
      guard let self else { return }
      for await devices in Wearables.shared.devicesStream() {
        self.availableDevices = devices
        #if DEBUG && canImport(MWDATMockDevice)
          self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
      }
    }
  }

  // MARK: - Public Actions

  /// Start the registration flow with Meta AI.
  public func connectGlasses() {
    guard case .idle = state else { return }

    didInitiateRegistration = true
    state = .registering

    Task {
      do {
        try await Wearables.shared.startRegistration()
      } catch let error as RegistrationError {
        state = .failed("Registration failed: \(error.description)")
      } catch {
        state = .failed("Registration failed: \(error.localizedDescription)")
      }
    }
  }

  /// Unregister from Meta AI.
  public func disconnectGlasses() {
    Task {
      do {
        try await Wearables.shared.startUnregistration()
      } catch let error as UnregistrationError {
        state = .failed("Disconnect failed: \(error.description)")
      } catch {
        state = .failed("Disconnect failed: \(error.localizedDescription)")
      }
    }
  }

  /// Request camera permission from the Meta AI companion app.
  /// Called by MetaGlassesFrameProvider before streaming.
  /// Returns true if permission is granted.
  ///
  /// Note: `checkPermissionStatus` always throws PermissionError in developer mode
  /// (MetaAppID = "0"), so we skip it and rely on our persisted flag instead.
  /// `requestPermission` is only called on first-ever grant.
  public func ensureCameraPermission() async -> Bool {
    // Already granted (persisted across launches) — skip entirely
    if permissionGranted {
      if state != .ready && state != .streaming {
        state = .ready
      }
      return true
    }

    guard isRegistered else { return false }

    // First-time permission request — this will leave the app to Meta AI
    state = .requestingPermission
    do {
      let status = try await Wearables.shared.requestPermission(.camera)
      if status == .granted {
        permissionGranted = true
        state = .ready
        return true
      } else {
        state = .failed("Camera permission denied. Grant access in the Meta AI app.")
        return false
      }
    } catch {
      state = .failed("Camera permission request failed: \(error.localizedDescription)")
      return false
    }
  }

  /// Called by MetaGlassesFrameProvider when the stream session state changes.
  public func reportStreamState(_ streamState: StreamSessionState) {
    switch streamState {
    case .streaming:
      state = .streaming
    case .stopped:
      // Only go back to ready if we were streaming; don't overwrite a failure
      if state == .streaming { state = .ready }
    case .waitingForDevice:
      if state == .streaming { state = .ready }
    default:
      break
    }
  }

  /// Called by MetaGlassesFrameProvider when streaming fails to start (e.g. no devices).
  public func reportStreamFailure(_ reason: String) {
    state = .failed(reason)
  }

  /// Reset from a failed state back to the best available state.
  /// Called when the user explicitly re-enables glasses mode.
  public func resetFailure() {
    guard case .failed = state else { return }
    // Figure out where we actually are based on SDK state
    let sdkState = Wearables.shared.registrationState
    if sdkState == .registered {
      if permissionGranted {
        state = .ready
      } else {
        state = .registered
      }
    } else {
      state = .idle
    }
  }

  // MARK: - Mock Device Support

  #if DEBUG && canImport(MWDATMockDevice)
    public func addMockDevice() {
      guard
        let videoURL = Bundle.main.url(
          forResource: MetaGlassesConfig.mockVideoFileName,
          withExtension: MetaGlassesConfig.mockVideoFileExtension)
      else {
        state = .failed(
          "Mock video file '\(MetaGlassesConfig.mockVideoFileName).\(MetaGlassesConfig.mockVideoFileExtension)' not found in bundle."
        )
        return
      }

      let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
      mockDevice.powerOn()
      mockDevice.unfold()

      let cameraKit = mockDevice.getCameraKit()
      Task {
        await cameraKit.setCameraFeed(fileURL: videoURL)
        self.hasMockDevice = true
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
