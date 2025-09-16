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
    print("Creating camera preview view controller...")
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

    print("Preview view controller created with frame: \(preview.frame)")
    return vc
  }

  func updateUIViewController(_ uiVC: UIViewController, context: Context) {
    print("Updating camera preview view controller (isRunning: \(isRunning))")
    let capture = context.coordinator.videoCapture

    // Update delegate if needed
    if capture.delegate !== delegate {
      print("Updating capture delegate")
      capture.delegate = delegate
    }

    // Start/stop capture as needed
    if isRunning {
      DispatchQueue.main.async {
        print("Starting capture from update")
        context.coordinator.setupIfNeeded()
        // Only start if not already running to avoid duplicate starts
        if !capture.isRunning {
          capture.start()
        }
      }
    } else {
      print("Stopping capture from update")
      capture.stop()
    }
  }

  // 4️⃣ Define the Coordinator
  class Coordinator: ObservableObject {
    let videoCapture: FrameProvider
    weak var delegate: FrameProviderDelegate?
    private var hasSetUpSession = false

    init(
      delegate: FrameProviderDelegate?,
      source: CaptureSourceType
    ) {
      self.delegate = delegate
      switch source {
      case .arKit:
        self.videoCapture = ARVideoCapture()
      case .videoFile:
        self.videoCapture = VideoFileFrameProvider()
      default:
        self.videoCapture = VideoCapture()
      }
      self.videoCapture.delegate = delegate
    }

    func setupIfNeeded() {
      guard !hasSetUpSession else { return }
      videoCapture.setupSession()
      hasSetUpSession = true
    }
  }
}
