import ARKit
import RealityKit
//
//  CameraPreviewView.swift
//  SwiftUI wrapper for ARVideoCapture to preview ARView and deliver frames + depth lookup
//
import SwiftUI
import UIKit

/// SwiftUI wrapper to embed ARVideoCapture's previewView and receive depth-enabled frames.
struct CameraPreviewWrapper: View {
  @Binding var isRunning: Bool
  weak var delegate: FrameProviderDelegate?
  var source: CaptureSourceType
  var body: some View {
    #if DEBUG
      if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
        Color.black
          .overlay(Text("Camera Preview").foregroundColor(.white))
      } else {
        #if targetEnvironment(simulator)
          CameraPreviewView(isRunning: $isRunning, delegate: delegate, source: .videoFile)
        #else
          CameraPreviewView(isRunning: $isRunning, delegate: delegate, source: source)
        #endif
      }
    #else
      CameraPreviewView(isRunning: $isRunning, delegate: delegate, source: source)
    #endif
  }
}
struct CameraPreviewView: UIViewControllerRepresentable {
  @Binding var isRunning: Bool
  weak var delegate: FrameProviderDelegate?
  var source: CaptureSourceType
  // 1️⃣ Remove your arCapture from here entirely

  /// 2️⃣ Create a coordinator that WILL hold it
  func makeCoordinator() -> Coordinator {
    Coordinator(delegate: delegate, source: source)
  }

  func makeUIViewController(context: Context) -> UIViewController {
    let vc = UIViewController()
    vc.view.backgroundColor = .black

    // Use the coordinator's video capture
    let capture = context.coordinator.videoCapture
    let preview = capture.previewView

    // Configure preview view
    preview.frame = vc.view.bounds
    preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    preview.contentMode = .scaleAspectFill
    preview.clipsToBounds = true

    // Add and configure the preview view
    vc.view.addSubview(preview)
    vc.view.sendSubviewToBack(preview)

    // Set delegate and start capture if needed
    capture.delegate = delegate

    // Set up the session and start capture if needed
    if isRunning {
      DispatchQueue.main.async {
        context.coordinator.setupIfNeeded()
        capture.start()
      }
    }

    return vc
  }

  func updateUIViewController(_ uiVC: UIViewController, context: Context) {
    // Check if source changed and swap provider if needed
    let sourceChanged = context.coordinator.updateSource(
      source, delegate: delegate, parentView: uiVC.view)

    let capture = context.coordinator.videoCapture

    // Update delegate if needed
    if capture.delegate !== delegate {
      capture.delegate = delegate
    }

    // Start/stop capture as needed
    if isRunning {
      DispatchQueue.main.async {
        context.coordinator.setupIfNeeded()
        // Only start if not already running to avoid duplicate starts
        if !capture.isRunning {
          capture.start()
        }
      }
    } else {
      capture.stop()
    }
  }

  // 4️⃣ Define the Coordinator
  class Coordinator: ObservableObject {
    var videoCapture: FrameProvider
    weak var delegate: FrameProviderDelegate?
    private var hasSetUpSession = false
    private(set) var currentSource: CaptureSourceType

    init(
      delegate: FrameProviderDelegate?,
      source: CaptureSourceType
    ) {
      self.delegate = delegate
      self.currentSource = source
      self.videoCapture = Self.createProvider(for: source)
      self.videoCapture.delegate = delegate
    }

    private static func createProvider(for source: CaptureSourceType) -> FrameProvider {
      switch source {
      case .arKit:
        return ARVideoCapture()
      case .videoFile:
        return VideoFileFrameProvider()
      case .metaGlasses:
        return MetaGlassesFrameProvider()
      default:
        return VideoCapture()
      }
    }

    @discardableResult
    func updateSource(
      _ newSource: CaptureSourceType, delegate: FrameProviderDelegate?, parentView: UIView
    ) -> Bool {
      guard newSource != currentSource else { return false }

      // Remove old preview view
      let oldPreview = videoCapture.previewView
      oldPreview.removeFromSuperview()

      // Stop old provider
      if videoCapture.isRunning {
        videoCapture.stop()
      }

      // Create new provider
      currentSource = newSource
      videoCapture = Self.createProvider(for: newSource)
      videoCapture.delegate = delegate
      hasSetUpSession = false

      // Add new preview view
      let newPreview = videoCapture.previewView
      newPreview.frame = parentView.bounds
      newPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      newPreview.contentMode = .scaleAspectFill
      newPreview.clipsToBounds = true
      parentView.addSubview(newPreview)
      parentView.sendSubviewToBack(newPreview)

      return true
    }

    func setupIfNeeded() {
      guard !hasSetUpSession else { return }
      videoCapture.setupSession()
      hasSetUpSession = true
    }
  }
}
