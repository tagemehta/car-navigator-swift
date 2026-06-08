import Combine
import SwiftUI
import UIKit

/// A self-contained subtree that owns the `CameraViewModel` and everything that depends on it.
///
/// Changing the `id` of this view from the parent **destroys** the existing
/// `CameraViewModel` (and its entire pipeline) and builds a fresh one, giving us
/// a deterministic full-reset without ad-hoc clean-up code.
struct DetectorContainer: View {
  // MARK: – External bindings
  @Binding var isRunning: Bool

  // MARK: – Immutable configuration
  let description: String
  let targetClasses: [String]
  let settings: Settings
  let isParatransitMode: Bool

  // MARK: – Dependencies
  @ObservedObject private var debugOverlayModel = AppContainer.shared.debugOverlayModel
  // COMMENTED OUT FOR APP STORE SUBMISSION
  @EnvironmentObject private var glassesVM: MetaGlassesViewModel
  @EnvironmentObject private var router: AppRouter

  // Track capture source as state so we can update it reactively
  @State private var currentCaptureSource: CaptureSourceType = .avFoundation

  // Whether the detector is currently on screen. The camera/stream only runs
  // while visible, so navigating away stops it and returning starts it fresh.
  // This is what re-runs the glasses connection checks after you leave (e.g. to
  // fix Settings) and come back, instead of getting stuck on "Connecting".
  @State private var isOnScreen = true

  /// The camera should capture only when the user hasn't paused AND the detector
  /// is on screen.
  private var captureActive: Binding<Bool> {
    Binding(
      get: { isRunning && isOnScreen },
      set: { isRunning = $0 }
    )
  }

  // MARK: – StateObject (lifetime tied to this view instance)
  @StateObject private var detectionModel: CameraViewModel

  // Custom init so we can inject dynamic parameters into the StateObject.
  init(
    isRunning: Binding<Bool>,
    description: String,
    targetClasses: [String],
    settings: Settings,
    isParatransitMode: Bool = false
  ) {
    _isRunning = isRunning
    self.description = description
    self.targetClasses = targetClasses
    self.settings = settings
    self.isParatransitMode = isParatransitMode
    _detectionModel = StateObject(
      wrappedValue: CameraViewModel(
        targetClasses: targetClasses,
        targetTextDescription: description,
        settings: settings,
        isParatransitMode: isParatransitMode))
  }

  // MARK: - Computed Properties

  /// Determines the capture source purely from durable user settings.
  ///
  /// The source is intentionally NOT derived from volatile glasses readiness
  /// flags (registration / device discovery / stream state). Doing so previously
  /// caused a cold-start race where the source flip-flopped and settled on the
  /// phone camera. When the user has selected glasses, the source is always
  /// `.metaGlasses`; connection, permission, and errors are surfaced as an
  /// overlay (see `GlassesPhaseOverlay`) rather than a silent camera fallback.
  private func computeCaptureSource() -> CaptureSourceType {
    // COMMENTED OUT FOR APP STORE SUBMISSION - begin Meta glasses capture source
    if FeatureFlags.metaGlassesEnabled && settings.useMetaGlasses {
      return .metaGlasses
    }
    // COMMENTED OUT FOR APP STORE SUBMISSION - end Meta glasses capture source
    if settings.useARMode {
      return .arKit
    }
    return .avFoundation
  }

  // MARK: – View
  var body: some View {
    ZStack {
      // Camera feed
      CameraPreviewWrapper(
        isRunning: captureActive,
        delegate: detectionModel,
        source: currentCaptureSource
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // COMMENTED OUT FOR APP STORE SUBMISSION - begin Meta glasses phase overlay
      // While glasses are the selected source, surface connection/error state
      // instead of silently falling back to the phone camera.
      if currentCaptureSource == .metaGlasses {
        GlassesPhaseOverlay(
          phase: glassesVM.displayPhase,
          onOpenSettings: { router.openMetaGlassesSettings() }
        )
      }
      // COMMENTED OUT FOR APP STORE SUBMISSION - end Meta glasses phase overlay

      // Bounding boxes
      BoundingBoxViewOverlay(boxes: $detectionModel.boundingBoxes)

      // FPS display
      VStack {
        HStack {
          Spacer()
          Text(String(format: "%.1f FPS", detectionModel.currentFPS))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black.opacity(0.5))
            .cornerRadius(8)
            .padding()
        }
        Spacer()
      }.accessibilityHidden(true)

      // Optional debug overlay
      if settings.debugOverlayEnabled {
        DebugOverlayView(model: debugOverlayModel, position: .bottom).accessibilityHidden(true)
      }
    }
    // Propagate orientation events so the model can react.
    .onRotate { _ in detectionModel.handleOrientationChange() }
    .onAppear {
      detectionModel.handleOrientationChange()
      currentCaptureSource = computeCaptureSource()
      // Returning to the detector restarts capture, which re-runs the glasses
      // connection/permission checks from a clean slate.
      isOnScreen = true
    }
    .onDisappear {
      // Leaving the detector stops the camera/stream so a fresh attempt runs on
      // return (and we don't keep the camera live off-screen).
      isOnScreen = false
    }
    // Source depends only on durable settings now, so recompute when those
    // change rather than on volatile glasses readiness flags.
    .onChange(of: settings.useMetaGlasses) { _, _ in
      currentCaptureSource = computeCaptureSource()
    }
    .onChange(of: settings.useARMode) { _, _ in
      currentCaptureSource = computeCaptureSource()
    }
  }
}

// COMMENTED OUT FOR APP STORE SUBMISSION - begin Meta glasses phase overlay

/// Full-screen overlay shown while the Meta glasses are the selected camera
/// source but frames are not yet flowing. Communicates connection progress and
/// terminal errors instead of silently falling back to the phone camera.
private struct GlassesPhaseOverlay: View {
  let phase: GlassesDisplayPhase
  /// Invoked when the user taps the Settings call-to-action. Placeholder until
  /// cross-tab navigation to the Meta Glasses settings section is wired up.
  let onOpenSettings: () -> Void

  var body: some View {
    Group {
      switch phase {
      case .streaming:
        // Frames are flowing — the live preview is visible, no overlay needed.
        EmptyView()
      case .connecting:
        container {
          ProgressView()
            .progressViewStyle(.circular)
            .tint(.white)
            .accessibilityHidden(true)
          statusText("Connecting to glasses…")
        }
      case .paused:
        container {
          statusText("Glasses paused")
          Text("Resuming when the device is ready…")
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.8))
            .accessibilityHidden(true)
        }
      case .needsSetup:
        container {
          statusText("Glasses not connected")
          Text("Connect your Meta glasses to stream from them.")
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .foregroundColor(.white.opacity(0.8))
            .accessibilityHidden(true)
          settingsButton
        }
      case .error(let message):
        container {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.largeTitle)
            .foregroundColor(.yellow)
            .accessibilityHidden(true)
          statusText(message)
          settingsButton
        }
      }
    }
    // Announce the phase to VoiceOver as it changes so a blind/low-vision user
    // hears the connection status without having to hunt for the overlay.
    .onAppear { announce(spokenStatus) }
    .onChange(of: spokenStatus) { _, newValue in announce(newValue) }
  }

  /// A status line that is a single, prominent VoiceOver element.
  private func statusText(_ text: String) -> some View {
    Text(text)
      .font(.headline)
      .multilineTextAlignment(.center)
      .foregroundColor(.white)
      .accessibilityElement()
      .accessibilityLabel(text)
      .accessibilityAddTraits(.isHeader)
  }

  /// The full spoken description for the current phase (label + guidance).
  private var spokenStatus: String {
    switch phase {
    case .streaming: return ""
    case .connecting: return "Connecting to glasses"
    case .paused: return "Glasses paused. Resuming when the device is ready."
    case .needsSetup:
      return "Glasses not connected. Connect your Meta glasses to stream from them."
    case .error(let message): return "Glasses error. \(message)"
    }
  }

  private func announce(_ message: String) {
    guard !message.isEmpty else { return }
    UIAccessibility.post(notification: .announcement, argument: message)
  }

  private var settingsButton: some View {
    Button(action: onOpenSettings) {
      Text("Open Meta Glasses Settings")
        .font(.headline)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.15))
        .cornerRadius(10)
        .foregroundColor(.white)
    }
    .accessibilityHint("Opens Meta glasses settings to connect or fix the connection.")
  }

  private func container<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ZStack {
      Color.black.opacity(0.85).ignoresSafeArea()
      VStack(spacing: 16) {
        content()
      }
      .padding(32)
    }
    // Treat the overlay as a modal layer so VoiceOver ignores the camera
    // preview behind it and focuses the status/actions.
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
  }
}

// COMMENTED OUT FOR APP STORE SUBMISSION - end Meta glasses phase overlay
