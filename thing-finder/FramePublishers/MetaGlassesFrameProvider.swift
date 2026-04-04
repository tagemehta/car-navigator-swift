// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

/*
 * MetaGlassesFrameProvider.swift
 *
 * FrameProvider implementation for Meta glasses using the DAT SDK.
 *
 * Lightweight adapter that delegates to StreamSessionViewModel.
 * Responsibility: forward frames from the view model to the FrameProviderDelegate.
 */

/*
import CoreMedia
import MWDATCamera
import MWDATCore
import UIKit

final class MetaGlassesFrameProvider: NSObject, FrameProvider {

  // MARK: - FrameProvider Protocol

  let previewView: UIView = UIView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .metaGlasses
  private(set) var isRunning: Bool = false

  // MARK: - Private

  private let streamSessionVM: StreamSessionViewModel
  private var frameObservationTask: Task<Void, Never>?
  /// Tracks the last frame sent to the delegate to avoid reprocessing the same UIImage.
  private weak var lastFrameRef: UIImage?

  private let previewImageView: UIImageView = {
    let iv = UIImageView()
    iv.contentMode = .scaleAspectFill
    iv.clipsToBounds = true
    return iv
  }()

  // MARK: - Init

  init(
    streamSessionViewModel: StreamSessionViewModel = MetaGlassesEnvironment.shared
      .streamSessionViewModel
  ) {
    self.streamSessionVM = streamSessionViewModel
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
    frameObservationTask?.cancel()
  }

  // MARK: - FrameProvider Methods

  func setupSession() {
    // Start observing frames from the view model
    frameObservationTask?.cancel()
    lastFrameRef = nil
    frameObservationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        if let frame = self.streamSessionVM.currentVideoFrame, frame !== self.lastFrameRef {
          self.lastFrameRef = frame
          self.previewImageView.image = frame
          // Use zero-copy pixel buffer extracted directly from the SDK's CMSampleBuffer
          if let pixelBuffer = self.streamSessionVM.currentPixelBuffer {
            self.delegate?.processFrame(self, buffer: pixelBuffer, depthAt: { _ in nil })
          }
        }
        try? await Task.sleep(nanoseconds: 33_000_000)  // ~30fps polling
      }
    }
  }

  func start() {
    guard !isRunning else { return }
    // Set synchronously so a concurrent stop() sees the updated flag immediately
    isRunning = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      let started = await self.streamSessionVM.handleStartStreaming()
      // Re-check isRunning: stop() may have been called while we were awaiting permission
      guard self.isRunning else {
        if started { await self.streamSessionVM.stopStreaming() }
        return
      }
      if started {
        self.setupSession()
      } else {
        self.isRunning = false
      }
    }
  }

  @MainActor func stop() {
    guard isRunning else { return }
    // Set synchronously so a concurrent start() Task sees the updated flag after its await
    isRunning = false
    frameObservationTask?.cancel()
    frameObservationTask = nil
    // Capture the current generation so the stop is skipped if a new provider
    // calls startStreaming() before this async task executes.
    let gen = streamSessionVM.streamGeneration
    Task { @MainActor [weak self] in
      await self?.streamSessionVM.stopStreaming(ifGeneration: gen)
    }
  }

}
*/
