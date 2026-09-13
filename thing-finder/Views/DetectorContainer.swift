import Combine
import SwiftUI

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
  @ObservedObject private var glasses = GlassesReadiness.shared

  // Track capture source as state so we can update it reactively
  @State private var currentCaptureSource: CaptureSourceType = .avFoundation

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
    // SwiftUI builds CameraPreviewView's coordinator BEFORE onAppear runs, so
    // this seed - not computeCaptureSource() - decides the first provider.
    // Seeding it unconditionally to .avFoundation meant the glasses source
    // could never be the initial one.
    _currentCaptureSource = State(
      initialValue: Self.initialCaptureSource(settings: settings))
  }

  /// Mirrors computeCaptureSource(), but callable from init.
  private static func initialCaptureSource(settings: Settings) -> CaptureSourceType {
    if FeatureFlags.metaGlassesEnabled && settings.useMetaGlasses
      && GlassesReadiness.shared.isReady
    {
      return .metaGlasses
    }
    if settings.useARMode {
      return .arKit
    }
    return .avFoundation
  }

  // MARK: - Computed Properties

  /// Determines the capture source based on settings and Meta glasses state.
  /// Falls back to phone camera immediately on failure or when glasses aren't usable.
  private func computeCaptureSource() -> CaptureSourceType {
    if FeatureFlags.metaGlassesEnabled && settings.useMetaGlasses && glasses.isReady {
      return .metaGlasses
    }
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
        isRunning: $isRunning,
        delegate: detectionModel,
        source: currentCaptureSource
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)

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
    }
    // Re-evaluate the capture source when the connection changes, so a
    // reconnect mid-session picks the glasses back up.
    .onChange(of: glasses.isReady) { _, _ in
      currentCaptureSource = computeCaptureSource()
    }
  }
}
