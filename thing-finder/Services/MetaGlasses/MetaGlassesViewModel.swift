// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

//
//  MetaGlassesViewModel.swift
//  thing-finder
//
//  Consolidated view model for Meta Ray-Ban glasses SDK lifecycle.
//  Replaces the previous split architecture (MetaGlassesManager, WearablesViewModel,
//  StreamSessionViewModel, MetaGlassesEnvironment).
//
//  Uses DAT SDK 0.7 DeviceSession + Stream capability model.
//
//  State machine:
//    unconfigured → idle → registering → registered → requestingPermission → ready → streaming
//                                                                                  ↘ paused
//                                                                                  ↘ failed(reason)
//                   ↑____________________________↙  (on unregistration)
//

import Combine
import CoreMedia
import Foundation
import MWDATCamera
import MWDATCore
import SwiftUI

#if DEBUG && canImport(MWDATMockDevice)
  import MWDATMockDevice
#endif

// MARK: - State Machine

/// Every possible state the Meta glasses integration can be in.
public enum GlassesState: Equatable {
  /// Wearables.configure() has not been called or failed.
  case unconfigured
  /// SDK configured but not registered with Meta AI.
  case idle
  /// Registration flow in progress (app may leave to Meta AI).
  case registering
  /// Registered with Meta AI, waiting for permission or stream start.
  case registered
  /// Camera permission request is in flight (app may leave to Meta AI).
  case requestingPermission
  /// Permission granted, ready to stream.
  case ready
  /// Actively streaming frames from glasses.
  case streaming
  /// Stream temporarily paused by the device.
  case paused
  /// A recoverable failure occurred; message explains why.
  case failed(String)
}

/// Streaming status for consumers that need a simpler enum.
public enum StreamingStatus {
  case streaming
  case stopped
  case waiting
}

/// UI-facing collapse of `GlassesState` for views that render a single
/// "what should the user see right now" overlay. Keeps `state` as the single
/// source of truth while giving the View one value to switch over.
public enum GlassesDisplayPhase: Equatable {
  /// SDK not configured or not registered — user must connect in Settings.
  case needsSetup
  /// Registering, requesting permission, or starting the stream.
  case connecting
  /// Frames are flowing.
  case streaming
  /// Stream temporarily paused by the device.
  case paused
  /// A terminal failure occurred; message explains why.
  case error(String)
}

// MARK: - MetaGlassesViewModel

@MainActor
public final class MetaGlassesViewModel: ObservableObject {
  public static let shared = MetaGlassesViewModel()

  // MARK: - Single source of truth

  @Published public private(set) var state: GlassesState = .unconfigured

  // MARK: - Frame output (push-based)

  @Published public private(set) var currentVideoFrame: UIImage?
  /// Zero-copy pixel buffer extracted directly from the SDK's CMSampleBuffer.
  public private(set) var currentPixelBuffer: CVPixelBuffer?

  // MARK: - Supplementary published state

  @Published public private(set) var availableDevices: [DeviceIdentifier] = []
  @Published public private(set) var hasActiveDevice: Bool = false
  /// The device identifier currently in `.connected` link state (if any).
  @Published public private(set) var connectedDeviceId: DeviceIdentifier?
  @Published public var hasMockDevice: Bool = false

  /// One-shot flag: set when registration completes via URL callback.
  @Published public var shouldShowRegistrationSuccess: Bool = false

  // MARK: - Derived convenience (read-only)

  /// True when glasses are usable as a camera source (permission granted).
  public var isReady: Bool {
    switch state {
    case .ready, .streaming, .paused: return true
    default: return false
    }
  }

  /// True when the stream is actively producing frames.
  public var isStreaming: Bool { state == .streaming }

  /// Collapsed phase for the detector overlay. Derived from `state`.
  public var displayPhase: GlassesDisplayPhase {
    switch state {
    case .unconfigured, .idle:
      return .needsSetup
    case .registering, .registered, .requestingPermission, .ready:
      return .connecting
    case .streaming:
      return .streaming
    case .paused:
      return .paused
    case .failed(let message):
      return .error(message)
    }
  }

  /// Streaming status for simpler consumers.
  public var streamingStatus: StreamingStatus {
    switch state {
    case .streaming: return .streaming
    case .ready, .paused: return .waiting
    default: return .stopped
    }
  }

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
    case .registered, .requestingPermission, .ready, .streaming, .paused: return true
    default: return false
    }
  }

  /// User-facing error message, derived from failed state.
  public var errorMessage: String? {
    if case .failed(let msg) = state { return msg }
    return nil
  }

  /// Registration state forwarded from the SDK for views that need it directly.
  @Published public private(set) var registrationState: RegistrationState = .unavailable

  // MARK: - Private

  private var didInitiateRegistration = false
  private var permissionGrantedThisSession: Bool = false
  @AppStorage("use_high_quality_glasses_stream") var useHighQualityStream: Bool = false
  private var registrationTask: Task<Void, Never>?
  private var deviceStreamTask: Task<Void, Never>?
  private var sessionStateTask: Task<Void, Never>?
  private var streamStateToken: (any AnyListenerToken)?
  private var videoFrameToken: (any AnyListenerToken)?
  private var errorToken: (any AnyListenerToken)?
  private var photoDataToken: (any AnyListenerToken)?
  private var compatibilityListenerTokens: [DeviceIdentifier: any AnyListenerToken] = [:]
  private var linkStateTokens: [DeviceIdentifier: any AnyListenerToken] = [:]

  /// The active DeviceSession (0.7 API).
  private var deviceSession: DeviceSession?
  /// The active Stream capability (0.7 API).
  private var stream: MWDATCamera.Stream?

  /// Incremented on each startStreaming call; stopStreaming is a no-op if the
  /// generation has advanced (prevents a stale stop from killing a new session).
  private(set) var streamGeneration: Int = 0

  /// The single in-flight streaming attempt. `startStreaming` coalesces
  /// concurrent callers onto this task so the shared singleton can't run two
  /// overlapping attempts (which would orphan a session or clobber `state`).
  /// Cancelled on teardown so an abandoned attempt stops promptly.
  private var streamingTask: Task<Bool, Never>?
  /// Identifies the current `streamingTask` (Task is a value type, so we can't
  /// compare by identity). Used to avoid clearing a newer task than our own.
  private var streamingTaskToken = 0

  /// How long to wait for a device session to reach `.started` before treating
  /// the attempt as a failure (no reachable glasses) instead of hanging.
  private static let sessionStartTimeoutNanos: UInt64 = 15_000_000_000  // 15s

  /// Result of waiting for a device session to start.
  private enum SessionStartOutcome {
    case started
    case stopped
    case timedOut
  }

  /// Result of waiting for the SDK to be ready to create a session.
  private enum ReadinessOutcome {
    case ready
    case notRegistered
    case noDevice
    /// The attempt was cancelled (e.g. streaming was torn down while waiting).
    case cancelled
  }

  // MARK: - Photo capture

  @Published public var capturedPhoto: UIImage?
  @Published public var showPhotoPreview: Bool = false

  // MARK: - Init

  private init() {
    configureSDK()
  }

  // MARK: - SDK Configuration

  private func configureSDK() {
    // Wearables.configure() is called once at app startup in ThingFinderApp.init().
    let currentState = Wearables.shared.registrationState
    registrationState = currentState
    handleSDKRegistrationState(currentState, isInitial: true)

    registrationTask = Task { [weak self] in
      guard let self else { return }
      for await sdkState in Wearables.shared.registrationStateStream() {
        self.registrationState = sdkState
        self.handleSDKRegistrationState(sdkState, isInitial: false)
      }
    }
  }

  private func handleSDKRegistrationState(_ sdkState: RegistrationState, isInitial: Bool) {
    switch sdkState {
    case .registered:
      if didInitiateRegistration && !isInitial {
        shouldShowRegistrationSuccess = true
      }
      didInitiateRegistration = false
      availableDevices = Wearables.shared.devices
      state = .registered
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
      permissionGrantedThisSession = false
    }
    didInitiateRegistration = false
    availableDevices = []
    teardownStream()
    deviceStreamTask?.cancel()
    deviceStreamTask = nil
  }

  // MARK: - Device Discovery

  private func startDeviceStream() {
    availableDevices = Wearables.shared.devices
    updateLinkStateMonitoring(for: availableDevices)

    deviceStreamTask?.cancel()
    deviceStreamTask = Task { [weak self] in
      guard let self else { return }
      for await devices in Wearables.shared.devicesStream() {
        self.availableDevices = devices
        self.updateLinkStateMonitoring(for: devices)
        self.monitorDeviceCompatibility(devices: devices)
        #if DEBUG && canImport(MWDATMockDevice)
          self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
      }
    }
  }

  private func updateLinkStateMonitoring(for devices: [DeviceIdentifier]) {
    let deviceSet = Set(devices)
    linkStateTokens = linkStateTokens.filter { deviceSet.contains($0.key) }

    // Check current link states and set up listeners
    var foundConnected: DeviceIdentifier?
    for deviceId in devices {
      guard let device = Wearables.shared.deviceForIdentifier(deviceId) else { continue }
      if device.linkState == .connected {
        foundConnected = deviceId
      }
      guard linkStateTokens[deviceId] == nil else { continue }
      let token = device.addLinkStateListener { [weak self] linkState in
        Task { @MainActor [weak self] in
          self?.refreshConnectedDevice()
        }
      }
      linkStateTokens[deviceId] = token
    }
    connectedDeviceId = foundConnected
    hasActiveDevice = foundConnected != nil || !devices.isEmpty
  }

  private func refreshConnectedDevice() {
    for deviceId in availableDevices {
      guard let device = Wearables.shared.deviceForIdentifier(deviceId) else { continue }
      if device.linkState == .connected {
        connectedDeviceId = deviceId
        hasActiveDevice = true
        return
      }
    }
    connectedDeviceId = nil
    hasActiveDevice = !availableDevices.isEmpty
  }

  private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
    let deviceSet = Set(devices)
    compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }

    for deviceId in devices {
      guard compatibilityListenerTokens[deviceId] == nil else { continue }
      guard let device = Wearables.shared.deviceForIdentifier(deviceId) else { continue }

      let deviceName = device.name
      let token = device.addCompatibilityListener { [weak self] compatibility in
        guard let self else { return }
        if compatibility == .deviceUpdateRequired {
          Task { @MainActor in
            self.state = .failed(
              "Device '\(deviceName)' requires an update to work with this app")
          }
        }
      }
      compatibilityListenerTokens[deviceId] = token
    }
  }

  // MARK: - Public Actions: Registration

  /// Start the registration flow with Meta AI.
  public func connectGlasses() {
    guard state == .idle || state == .unconfigured else { return }

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

  // MARK: - Public Actions: Permissions

  /// Request camera permission from the Meta AI companion app.
  /// Returns true if permission is granted.
  ///
  /// The non-interactive `checkPermissionStatus` reflects the persisted grant
  /// ("Allow always"), but it can only read it when a glasses device is
  /// *connected* — otherwise it throws `.noDeviceWithConnection`. So we poll the
  /// silent check while a connection comes up, and only fall back to the
  /// interactive prompt (which opens Meta AI) when the status is definitively
  /// `.denied`. This is what makes "Allow always" actually skip the prompt on a
  /// new session instead of re-prompting every launch.
  public func requestCameraPermission() async -> Bool {
    // Already verified this streaming session — skip redundant calls
    if permissionGrantedThisSession {
      if state != .ready && state != .streaming && state != .paused {
        state = .ready
      }
      return true
    }

    guard isRegistered else { return false }

    let deadline = DispatchTime.now().uptimeNanoseconds + Self.sessionStartTimeoutNanos
    while true {
      if Task.isCancelled { return false }
      do {
        let status = try await Wearables.shared.checkPermissionStatus(.camera)
        switch status {
        case .granted:
          #if DEBUG
            print("[MetaGlassesVM] checkPermissionStatus returned .granted (no prompt needed)")
          #endif
          permissionGrantedThisSession = true
          state = .ready
          return true
        case .denied:
          // Definitive: not granted (e.g. "Allow once" expired, or never
          // granted). A connection exists, so prompt interactively.
          return await requestCameraPermissionInteractive()
        @unknown default:
          return await requestCameraPermissionInteractive()
        }
      } catch let error as PermissionError {
        switch error {
        case .metaAINotInstalled:
          state = .failed("Install the Meta AI app to use your glasses.")
          return false
        case .noDevice, .noDeviceWithConnection, .connectionError, .requestTimeout,
          .requestInProgress, .internalError:
          // Can't read the persisted status yet (no live connection). Wait for
          // the device to connect and retry the silent check rather than
          // prompting — prompting here would defeat "Allow always".
          if DispatchTime.now().uptimeNanoseconds >= deadline {
            state = .failed(
              "Couldn't reach your glasses to check camera access. Make sure they're open, "
                + "worn, and connected.")
            return false
          }
          #if DEBUG
            print("[MetaGlassesVM] checkPermissionStatus transient (\(error)); waiting to retry")
          #endif
          do {
            try await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
          } catch {
            return false  // cancelled
          }
        @unknown default:
          return await requestCameraPermissionInteractive()
        }
      }
    }
  }

  /// Interactive permission request — opens Meta AI for the user to grant access.
  /// Only used when the silent check reports a definitive `.denied`.
  private func requestCameraPermissionInteractive() async -> Bool {
    state = .requestingPermission
    do {
      let status = try await Wearables.shared.requestPermission(.camera)
      if status == .granted {
        #if DEBUG
          print("[MetaGlassesVM] requestPermission returned .granted")
        #endif
        permissionGrantedThisSession = true
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

  // MARK: - Public Actions: Streaming (0.7 DeviceSession + Stream)

  /// Wait until the SDK is registered and at least one paired device is known,
  /// so `createSession` won't immediately throw "no eligible devices". Polls the
  /// MainActor-isolated published state (kept current by the registration and
  /// device streams) and is bounded by `sessionStartTimeoutNanos`.
  private func awaitStreamReadiness() async -> ReadinessOutcome {
    let start = DispatchTime.now().uptimeNanoseconds
    while true {
      if Task.isCancelled { return .cancelled }
      if isRegistered && !availableDevices.isEmpty { return .ready }
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      if elapsed >= Self.sessionStartTimeoutNanos {
        return isRegistered ? .noDevice : .notRegistered
      }
      do {
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
      } catch {
        return .cancelled  // sleep throws on cancellation
      }
    }
  }

  /// Create a DeviceSession, retrying briefly because device discovery can still
  /// be settling right after a permission round-trip (createSession throws
  /// synchronously when no device is eligible yet). Rethrows the last error.
  private func createSessionWithRetry(
    wearables: any WearablesInterface, selector: AutoDeviceSelector
  ) async throws -> DeviceSession {
    let maxAttempts = 5
    var lastError: Error?
    for attempt in 1...maxAttempts {
      do {
        return try wearables.createSession(deviceSelector: selector)
      } catch {
        lastError = error
        #if DEBUG
          print("[MetaGlassesVM] createSession attempt \(attempt)/\(maxAttempts) failed: \(error)")
        #endif
        if attempt < maxAttempts {
          try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s; propagates cancellation
        }
      }
    }
    throw lastError!
  }

  /// Start streaming from the glasses.
  ///
  /// Coalesces concurrent callers onto a single in-flight attempt. The shared
  /// singleton can be driven by multiple frame providers and SwiftUI re-renders,
  /// and the attempt has long suspension points (readiness waits, permission
  /// round-trip), so without this two overlapping attempts could create
  /// duplicate sessions or clobber each other's state.
  /// Returns true if streaming was successfully initiated.
  @discardableResult
  public func startStreaming(highQuality: Bool = false) async -> Bool {
    if let existing = streamingTask {
      return await existing.value
    }
    streamingTaskToken &+= 1
    let token = streamingTaskToken
    let task = Task { await self.runStreamingAttempt(highQuality: highQuality) }
    streamingTask = task
    let result = await task.value
    // Only clear if a newer attempt hasn't replaced ours in the meantime.
    if streamingTaskToken == token { streamingTask = nil }
    return result
  }

  /// The actual streaming attempt. Runs inside `streamingTask`; checks
  /// `Task.isCancelled` at its suspension points so a teardown during startup
  /// stops promptly without writing a stale `.failed` state.
  private func runStreamingAttempt(highQuality: Bool) async -> Bool {
    // On a cold launch the SDK re-registers and re-discovers paired devices
    // asynchronously. Creating a session before a device is known throws
    // "no eligible devices available", so wait (bounded) for the SDK to be
    // ready before doing anything. The overlay shows "connecting" meanwhile.
    switch await awaitStreamReadiness() {
    case .ready:
      break
    case .cancelled:
      return false
    case .notRegistered:
      state = .failed("Connect your Meta glasses in Settings to stream from them.")
      return false
    case .noDevice:
      state = .failed("No glasses found. Make sure they're open, worn, and connected.")
      return false
    }

    // Ensure camera permission first
    guard await requestCameraPermission() else { return false }

    // The permission request leaves the app for Meta AI and returns via URL
    // callback. While we were backgrounded the device list can briefly clear as
    // Bluetooth reconnects, so re-confirm a device is known before creating the
    // session (otherwise createSession throws "no eligible devices available").
    switch await awaitStreamReadiness() {
    case .ready:
      break
    case .cancelled:
      return false
    default:
      state = .failed("No glasses found. Make sure they're open, worn, and connected.")
      return false
    }

    streamGeneration += 1

    let resolution: StreamingResolution = highQuality ? .high : .medium
    let frameRate: UInt = highQuality ? 30 : 24

    do {
      let wearables = Wearables.shared

      // Always use AutoDeviceSelector — it waits for a device to become eligible
      // even if currently connected but not ready (e.g. hinges closed).
      let selector = AutoDeviceSelector(wearables: wearables)
      #if DEBUG
        print(
          "[MetaGlassesVM] startStreaming: creating session with AutoDeviceSelector. devices=\(availableDevices)"
        )
        for devId in availableDevices {
          let dev = wearables.deviceForIdentifier(devId)
          print(
            "[MetaGlassesVM]   device \(devId): linkState=\(String(describing: dev?.linkState))")
        }
      #endif

      // Device discovery can still be settling immediately after the permission
      // round-trip, so retry createSession briefly before giving up.
      let session = try await createSessionWithRetry(wearables: wearables, selector: selector)
      #if DEBUG
        print(
          "[MetaGlassesVM] session created, current state: \(session.state). Calling start()...")
      #endif
      try session.start()
      #if DEBUG
        print("[MetaGlassesVM] session.start() called, state now: \(session.state)")
      #endif

      // Capture session errors in parallel to understand why it stops
      var sessionError: DeviceSessionError?
      let errorTask = Task {
        for await error in session.errorStream() {
          #if DEBUG
            print("[MetaGlassesVM] session errorStream: \(error)")
          #endif
          sessionError = error
        }
      }

      // Wait for the device session to reach the started state, but never wait
      // forever: AutoDeviceSelector keeps the session in .starting until a device
      // is ready, so if no glasses are reachable we'd otherwise hang in
      // "connecting" indefinitely. Race the state stream against a timeout.
      let outcome: SessionStartOutcome = await withTaskGroup(of: SessionStartOutcome.self) {
        group in
        group.addTask {
          for await sessionState in session.stateStream() {
            #if DEBUG
              print("[MetaGlassesVM] session stateStream: \(sessionState)")
            #endif
            if sessionState == .started { return .started }
            if sessionState == .stopped { return .stopped }
          }
          return .stopped
        }
        group.addTask {
          try? await Task.sleep(nanoseconds: Self.sessionStartTimeoutNanos)
          return .timedOut
        }
        let first = await group.next() ?? .stopped
        group.cancelAll()
        return first
      }
      errorTask.cancel()

      // If we were torn down while waiting, stop the freshly-created session and
      // bail without writing a stale terminal state.
      if Task.isCancelled {
        session.stop()
        return false
      }

      switch outcome {
      case .started:
        break
      case .timedOut:
        session.stop()
        state = .failed("No glasses found. Make sure they're open, worn, and connected.")
        return false
      case .stopped:
        if sessionError == .datAppOnTheGlassesUpdateRequired {
          state = .failed("The DAT app on your glasses needs an update. Opening Meta AI...")
          try? await Wearables.shared.openDATGlassesAppUpdate()
        } else if sessionError == .dwaUnavailable {
          state = .failed(
            "DAT service unavailable on glasses. Restart your glasses and try again.")
        } else if let err = sessionError {
          state = .failed("Device session stopped: \(err.localizedDescription)")
        } else {
          state = .failed(
            "Device session stopped. Ensure glasses are open, on your head, and connected.")
        }
        return false
      }

      let config = StreamConfiguration(
        videoCodec: .raw,
        resolution: resolution,
        frameRate: frameRate
      )
      guard let newStream = try session.addStream(config: config) else {
        state = .failed("Failed to add stream. Ensure device session is started.")
        return false
      }

      // Final cancellation check before we take ownership: otherwise a teardown
      // that already ran would leave this session/stream with nothing to stop it.
      if Task.isCancelled {
        Task { await newStream.stop() }
        session.stop()
        return false
      }

      // Store references
      self.deviceSession = session
      self.stream = newStream

      // Observe session state changes
      sessionStateTask?.cancel()
      sessionStateTask = Task { [weak self] in
        guard let self else { return }
        for await sessionState in session.stateStream() {
          switch sessionState {
          case .paused:
            self.state = .paused
          case .stopped:
            self.teardownStream()
            if self.state == .streaming || self.state == .paused {
              self.state = .ready
            }
          case .started:
            if self.state == .paused {
              self.state = .streaming
            }
          default:
            break
          }
        }
      }

      // Observe stream state, frames, errors, and photo captures
      subscribeStreamListeners(to: newStream)

      // Start the stream capability
      await newStream.start()
      return true

    } catch {
      #if DEBUG
        print("[MetaGlassesVM] DeviceSessionError: \(error)")
      #endif
      // A cancellation (teardown during startup) is not a user-facing failure.
      if Task.isCancelled || error is CancellationError {
        return false
      }
      state = .failed("Failed to start streaming: \(error.localizedDescription)")
      return false
    }
  }

  /// True when a stream session exists and is still active.
  public var hasActiveStream: Bool {
    stream != nil && deviceSession != nil
  }

  /// Stop observing frames without destroying the session.
  /// Call this when the view disappears but the user may return.
  public func pauseFrameDelivery() {
    videoFrameToken = nil
    streamStateToken = nil
    errorToken = nil
    photoDataToken = nil
    // Defer @Published changes to avoid publishing during a view update cycle
    DispatchQueue.main.async { [weak self] in
      self?.currentVideoFrame = nil
      self?.currentPixelBuffer = nil
    }
  }

  /// Re-subscribe to frames from an existing active stream.
  /// Returns true if the stream was still active and re-subscribed.
  public func resumeFrameDelivery() -> Bool {
    guard let activeStream = stream else { return false }

    // The SDK stream may have hit a terminal state while delivery was paused
    // (e.g. the device disconnected). Don't claim it's active in that case.
    switch activeStream.state {
    case .stopping, .stopped:
      return false
    default:
      break
    }

    subscribeStreamListeners(to: activeStream)

    if state != .streaming {
      state = .streaming
    }
    return true
  }

  /// Subscribe to all stream lifecycle publishers (state, frames, errors,
  /// photos), replacing any existing tokens. Used by both initial startup and
  /// resume so a pause/resume cycle keeps observing every event.
  private func subscribeStreamListeners(to stream: MWDATCamera.Stream) {
    streamStateToken = stream.statePublisher.listen { [weak self] (streamState: StreamState) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        switch streamState {
        case .streaming:
          self.state = .streaming
        case .waitingForDevice:
          if self.state == .streaming { self.state = .ready }
        case .stopped:
          if self.state == .streaming || self.state == .paused {
            self.state = .ready
          }
        case .paused:
          self.state = .paused
        default:
          break
        }
      }
    }

    videoFrameToken = stream.videoFramePublisher.listen { [weak self] (frame: VideoFrame) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.currentPixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
        if let image = frame.makeUIImage() {
          self.currentVideoFrame = image
        }
      }
    }

    errorToken = stream.errorPublisher.listen { [weak self] (error: StreamError) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.state = .failed(Self.formatStreamError(error))
      }
    }

    photoDataToken = stream.photoDataPublisher.listen { [weak self] (photoData: PhotoData) in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let image = UIImage(data: photoData.data) {
          self.capturedPhoto = image
          self.showPhotoPreview = true
        }
      }
    }
  }

  /// Fully stop and tear down the streaming session.
  /// - Parameter generation: If provided, the stop is skipped when the stream
  ///   generation has advanced. Pass `nil` to stop unconditionally.
  public func stopStreaming(ifGeneration generation: Int? = nil) {
    if let generation, generation != streamGeneration {
      return
    }
    teardownStream()
    if state == .streaming || state == .paused {
      state = .ready
    }
  }

  /// Capture a still photo while streaming.
  @discardableResult
  public func capturePhoto() -> Bool {
    stream?.capturePhoto(format: .jpeg) ?? false
  }

  /// Dismiss photo preview.
  public func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  // MARK: - State Recovery

  /// Reset from a failed state back to the best available state.
  public func resetFailure() {
    guard case .failed = state else { return }
    let sdkState = Wearables.shared.registrationState
    if sdkState == .registered {
      if permissionGrantedThisSession {
        state = .ready
      } else {
        state = .registered
      }
    } else {
      state = .idle
    }
  }

  /// Dismiss error (convenience for views).
  public func dismissError() {
    if case .failed = state {
      resetFailure()
    }
  }

  // MARK: - Private Helpers

  private func teardownStream() {
    // Cancel any in-flight startup attempt so it stops promptly instead of
    // finishing and re-creating a session we're trying to tear down.
    streamingTask?.cancel()
    streamingTask = nil

    streamStateToken = nil
    videoFrameToken = nil
    errorToken = nil
    photoDataToken = nil
    sessionStateTask?.cancel()
    sessionStateTask = nil

    if let stream = stream {
      Task { await stream.stop() }
    }
    deviceSession?.stop()
    stream = nil
    deviceSession = nil

    currentVideoFrame = nil
    currentPixelBuffer = nil
  }

  private static func formatStreamError(_ error: StreamError) -> String {
    switch error {
    case .deviceNotFound: return "Device not found. Ensure your glasses are connected."
    case .deviceNotConnected: return "Device disconnected. Check your Bluetooth connection."
    case .timeout: return "Streaming timed out. Please try again."
    case .videoStreamingError: return "Video streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Grant access in the Meta AI app."
    case .hingesClosed: return "Glasses hinges are closed. Open them to stream."
    case .thermalCritical: return "Device is overheating. Streaming paused."
    case .thermalEmergency: return "Device thermal emergency. Streaming stopped."
    case .peakPowerShutdown: return "Peak power shutdown. Streaming stopped."
    case .batteryCritical: return "Battery critically low. Streaming stopped."
    case .internalError: return "An internal streaming error occurred."
    @unknown default: return "An unknown streaming error occurred."
    }
  }

  // MARK: - Mock Device Support

  #if DEBUG && canImport(MWDATMockDevice)
    public func addMockDevice() {
      guard
        let videoURL = Bundle.main.url(
          forResource: "mock_video",
          withExtension: "mov")
      else {
        state = .failed("Mock video file 'mock_video.mov' not found in bundle.")
        return
      }

      MockDeviceKit.shared.enable()
      let mockDevice = MockDeviceKit.shared.pairRaybanMeta()

      Task {
        mockDevice.powerOn()
        mockDevice.unfold()
        mockDevice.don()

        let camera = mockDevice.services.camera
        camera.setCameraFeed(fileURL: videoURL)
        self.hasMockDevice = true
      }
    }

    public func removeMockDevice() {
      for device in MockDeviceKit.shared.pairedDevices {
        MockDeviceKit.shared.unpairDevice(device)
      }
      MockDeviceKit.shared.disable()
      hasMockDevice = false
    }
  #endif
}
