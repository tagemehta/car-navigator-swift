//  VideoFileFrameProvider.swift
//  thing-finder
//
//  Streams frames from a local movie file so that the rest of the pipeline
//  can be exercised in the simulator *without* a live camera.
//  It mirrors the behaviour of `VideoCapture` by:
//    • providing a ready-made preview layer that auto-rotates with
//      `UIDeviceOrientation` changes.
//    • (optionally) rotating the pixel buffers so that the buffer orientation
//      changes when the device rotates – useful for testing the image-rotation
//      logic in the pipeline.
//
//  Created by Cascade on 20/07/25.

import AVFoundation
import CoreImage
import UIKit

/// Streams frames from an `AVAsset` and conforms to `FrameProvider` so it can
/// be dropped into existing code that expects a live camera.
final class VideoFileFrameProvider: NSObject, FrameProvider {

  // MARK: ‑ FrameProvider

  let previewView: UIView = UIView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .videoFile
  private(set) var isRunning: Bool = false

  var deviceOrientation: UIInterfaceOrientation? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?.interfaceOrientation
  }
  func setupSession() {
    // No heavy AV plumbing needed – simply attach the player layer.
    playerLayer.videoGravity = .resizeAspectFill
    previewView.layer.addSublayer(playerLayer)
    previewView.clipsToBounds = true
    // Initial layout
    playerLayer.frame = previewView.bounds
  }

  func start() {
    guard !isRunning else { return }
    displayLink.isPaused = false
    player.play()
    isRunning = true
  }

  // MARK: - Video Looping

  @objc private func playerItemDidReachEnd(notification: Notification) {
    // Reset to beginning and play again
    player.seek(to: .zero)
    player.play()
  }

  func stop() {
    guard isRunning else { return }
    displayLink.isPaused = true
    player.pause()
    isRunning = false
  }

  // MARK: ‑ Init / deinit

  /// - Parameters:
  ///   - url: movie file URL.
  ///   - rotatesBuffers: when true, each frame is rotated to simulate how a
  ///     camera sensor’s buffer orientation changes with device rotation. Keep
  ///     *false* if the pipeline already expects a constant buffer orientation
  ///     (same as the live camera path).
  override init() {
    self.asset = AVURLAsset(url: Bundle.main.url(forResource: "IMG_3605", withExtension: "MOV")!)
    self.item = AVPlayerItem(asset: asset)
    self.rotatesBuffers = true

    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVImageBufferColorPrimariesKey as String: kCVImageBufferColorPrimaries_ITU_R_709_2,
      kCVImageBufferTransferFunctionKey as String: kCVImageBufferTransferFunction_sRGB,
      kCVImageBufferYCbCrMatrixKey as String: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
    ]
    self.output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
    item.add(output)

    self.player = AVPlayer(playerItem: item)
    self.playerLayer = AVPlayerLayer(player: player)
    // Prevent HDR highlights from blowing out in the preview.
    self.playerLayer.wantsExtendedDynamicRangeContent = false

    self.ciContext = CIContext()

    super.init()

    // Set up notification to loop the video when it reaches the end
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemDidReachEnd),
      name: .AVPlayerItemDidPlayToEndTime,
      object: item
    )

    displayLink = CADisplayLink(target: self, selector: #selector(tick))
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = true

    setupRotationObservation()
  }

  deinit {
    displayLink.invalidate()
    player.pause()
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: ‑ Rotation handling (preview)

  private func setupRotationObservation() {
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOrientationChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil)
    updatePreviewRotation()
  }

  @objc private func handleOrientationChange() {
    updatePreviewRotation()
  }

  private func updatePreviewRotation() {
    let angle: CGFloat
    switch deviceOrientation {
    case .portrait: angle = 0
    case .portraitUpsideDown: angle = 180
    case .landscapeLeft: angle = 270
    case .landscapeRight: angle = 90
    default: angle = 0
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let radians = angle * .pi / 180
      self.playerLayer.setAffineTransform(CGAffineTransform(rotationAngle: radians))
      self.playerLayer.frame = self.previewView.bounds
    }
  }

  // MARK: ‑ Display-link pump

  @objc private func tick() {
    let hostTime = CACurrentMediaTime()
    let itemTime = output.itemTime(forHostTime: hostTime)
    guard output.hasNewPixelBuffer(forItemTime: itemTime),
      let buf = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
    else { return }

    let finalBuf: CVPixelBuffer

    if rotatesBuffers {

      finalBuf = rotate(pixelBuffer: buf, to: deviceOrientation!) ?? buf
    } else {
      finalBuf = buf
    }

    delegate?.processFrame(self, buffer: finalBuf, depthAt: { _ in nil })
  }

  // MARK: ‑ Helpers

  /// Rotates the given buffer so that its content *appears* to have the same
  /// orientation behaviour as frames from the live camera.
  private func rotate(pixelBuffer: CVPixelBuffer, to ori: UIInterfaceOrientation) -> CVPixelBuffer?
  {
    let angle: CGFloat
    switch ori {
    case .portrait: angle = 0
    case .portraitUpsideDown: angle = .pi/2
    case .landscapeLeft: angle = .pi
    case .landscapeRight: angle = -.pi
    default: angle = 0
    }

    guard angle != 0 else { return pixelBuffer }

    let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: 1)
      .transformed(by: CGAffineTransform(rotationAngle: angle))
//    print(UIImage(ciImage: ciImage).jpegData(compressionQuality: 0.5)?.base64EncodedString())
    var newBuf: CVPixelBuffer?
    let w = Int(ciImage.extent.width)
    let h = Int(ciImage.extent.height)
    CVPixelBufferCreate(
      kCFAllocatorDefault, w, h,
      kCVPixelFormatType_32BGRA, nil, &newBuf)
    guard let dest = newBuf else { return pixelBuffer }

    ciContext.render(ciImage, to: dest)
    return dest
  }

  // MARK: ‑ Private state

  private let asset: AVAsset
  private let item: AVPlayerItem
  private let output: AVPlayerItemVideoOutput
  private let player: AVPlayer
  private let playerLayer: AVPlayerLayer
  private let ciContext: CIContext
  private var displayLink: CADisplayLink!
  private let rotatesBuffers: Bool
}
