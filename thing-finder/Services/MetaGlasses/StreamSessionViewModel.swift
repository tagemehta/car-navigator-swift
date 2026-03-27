//
//  StreamSessionViewModel.swift
//  thing-finder
//
//  Mirrors the Meta CameraAccess sample StreamSessionViewModel.
//

import CoreMedia
import MWDATCamera
import MWDATCore
import SwiftUI

@MainActor
final class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  /// Zero-copy pixel buffer extracted directly from the SDK's CMSampleBuffer.
  /// Prefer this over converting currentVideoFrame back to CVPixelBuffer.
  private(set) var currentPixelBuffer: CVPixelBuffer?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false

  var isStreaming: Bool { streamingStatus == .streaming }

  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private let streamSession: StreamSession

  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private var deviceMonitorTask: Task<Void, Never>?

  init(wearables: WearablesInterface = Wearables.shared) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: .raw,
      resolution: .high,
      frameRate: 30
    )
    self.streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    deviceMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await device in deviceSelector.activeDeviceStream() {
        await MainActor.run {
          self.hasActiveDevice = device != nil
        }
      }
    }

    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatus(from: state)
      }
    }

    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] frame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        // Extract pixel buffer zero-copy before makeUIImage() discards the sample buffer
        self.currentPixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
        if let image = frame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
        }
      }
    }

    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        self?.showErrorMessage(Self.format(error))
      }
    }

    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let image = UIImage(data: photoData.data) {
          self.capturedPhoto = image
          self.showPhotoPreview = true
        }
      }
    }

    updateStatus(from: streamSession.state)
  }

  /// Checks/requests camera permission and starts streaming if granted.
  /// Returns `true` if streaming was successfully initiated, `false` on permission denial or error.
  @discardableResult
  func handleStartStreaming() async -> Bool {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startStreaming()
        return true
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startStreaming()
        return true
      }
      showErrorMessage("Permission denied")
      return false
    } catch {
      showErrorMessage("Permission error: \(error.localizedDescription)")
      return false
    }
  }

  func startStreaming() async {
    await streamSession.start()
  }

  func stopStreaming() async {
    await streamSession.stop()
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func capturePhoto() {
    streamSession.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func updateStatus(from state: StreamSessionState) {
    switch state {
    case .streaming:
      streamingStatus = .streaming
    case .stopped:
      currentVideoFrame = nil
      currentPixelBuffer = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    }
  }

  private func showErrorMessage(_ message: String) {
    errorMessage = message
    showError = true
  }

  deinit {
    deviceMonitorTask?.cancel()
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil
    photoDataListenerToken = nil
  }

  private static func format(_ error: StreamSessionError) -> String {
    switch error {
    case .deviceNotFound: return "Device not found. Ensure your glasses are connected."
    case .deviceNotConnected: return "Device disconnected. Check your Bluetooth connection."
    case .timeout: return "Streaming timed out. Please try again."
    case .videoStreamingError: return "Video streaming failed. Please try again."
    case .permissionDenied: return "Camera permission denied. Grant access in the Meta AI app."
    case .hingesClosed: return "Glasses hinges are closed. Open them to stream."
    case .thermalCritical: return "Device is overheating. Streaming paused."
    case .internalError: return "An internal streaming error occurred."
    @unknown default: return "An unknown streaming error occurred."
    }
  }
}

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}
