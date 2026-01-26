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

  // MARK: – Dependencies
  @ObservedObject private var debugOverlayModel = AppContainer.shared.debugOverlayModel

  // MARK: – StateObject (lifetime tied to this view instance)
  @StateObject private var detectionModel: CameraViewModel

  // Custom init so we can inject dynamic parameters into the StateObject.
  init(
    isRunning: Binding<Bool>,
    description: String,
    targetClasses: [String],
    settings: Settings
  ) {
    _isRunning = isRunning
    self.description = description
    self.targetClasses = targetClasses
    self.settings = settings
    _detectionModel = StateObject(
      wrappedValue: CameraViewModel(
        targetClasses: targetClasses,
        targetTextDescription: description,
        settings: settings))
  }

  // MARK: – View
  var body: some View {
    ZStack {
      // Camera feed
      CameraPreviewWrapper(
        isRunning: $isRunning,
        delegate: detectionModel,
        source: settings.useMetaGlasses
          ? .metaGlasses : (settings.useARMode ? .arKit : .avFoundation)
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
      }

      // Optional debug overlay
      if settings.debugOverlayEnabled {
        DebugOverlayView(model: debugOverlayModel, position: .bottom)
      }
    }
    // Propagate orientation events so the model can react.
    .onRotate { _ in detectionModel.handleOrientationChange() }
    .onAppear { detectionModel.handleOrientationChange() }
  }
}
