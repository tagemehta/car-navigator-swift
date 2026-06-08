// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

/*
 * MetaGlassesFrameProvider.swift
 *
 * FrameProvider implementation for Meta glasses using the DAT SDK 0.7.
 *
 * Push-based adapter: subscribes to MetaGlassesViewModel's frame publisher
 * and forwards each new frame to the FrameProviderDelegate. No polling.
 */

import Combine
import CoreMedia
import MWDATCamera
import MWDATCore
import UIKit

final class MetaGlassesFrameProvider: NSObject, @preconcurrency FrameProvider {

  // MARK: - FrameProvider Protocol

  let previewView: UIView = UIView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .metaGlasses
  private(set) var isRunning: Bool = false

  // MARK: - Private

  private let glassesVM: MetaGlassesViewModel
  private var frameCancellable: AnyCancellable?

  private let previewImageView: UIImageView = {
    let iv = UIImageView()
    iv.contentMode = .scaleAspectFill
    iv.clipsToBounds = true
    return iv
  }()

  // MARK: - Init

  @MainActor init(glassesViewModel: MetaGlassesViewModel) {
    self.glassesVM = glassesViewModel
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
    frameCancellable?.cancel()
  }

  // MARK: - FrameProvider Methods

  @MainActor func setupSession() {
    // Subscribe to frames from the view model (push-based, no polling)
    frameCancellable?.cancel()
    frameCancellable = glassesVM.$currentVideoFrame
      .compactMap { $0 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] frame in
        guard let self, self.isRunning else { return }
        self.previewImageView.image = frame
        if let pixelBuffer = self.glassesVM.currentPixelBuffer {
          self.delegate?.processFrame(self, buffer: pixelBuffer, depthAt: { _ in nil })
        }
      }
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    Task { @MainActor [weak self] in
      guard let self else { return }

      // If the stream is already active (e.g. coming back to the tab),
      // just re-subscribe to frames instead of creating a new session.
      if self.glassesVM.hasActiveStream {
        let resumed = self.glassesVM.resumeFrameDelivery()
        if resumed {
          self.setupSession()
          return
        }
      }

      let started = await self.glassesVM.startStreaming(
        highQuality: self.glassesVM.useHighQualityStream)
      guard self.isRunning else {
        if started {
          self.glassesVM.stopStreaming()
        }
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
    isRunning = false
    frameCancellable?.cancel()
    frameCancellable = nil
    // Pause frame delivery but keep the session alive for quick resume
    glassesVM.pauseFrameDelivery()
  }

}
