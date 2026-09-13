//
//  ExtentosFrameProvider.swift
//  thing-finder
//
//  FrameProvider backed by the Extentos SDK, so glasses slot in beside the
//  ARKit / AVFoundation / video-file sources without the detection pipeline
//  changing.
//
//  Frames are requested as RAW planar I420 rather than JPEG: that is the
//  documented path for CV pipelines, and it avoids an encode on the glasses
//  plus a decode here on every frame. The SDK guarantees the same contract on
//  real glasses and in the browser simulator.
//
//  I420 -> BGRA goes through vImage rather than Core Image. CIImage on a
//  planar YUV CVPixelBuffer rendered black here even with YCbCrMatrix,
//  primaries and transfer function attached (measured: input mean luma 118,
//  converted output mean 0). vImage takes an explicit conversion matrix and
//  pixel range, so there is nothing left to infer.
//

import Accelerate
import CoreVideo
import GlassesCore
import UIKit

/// Holds the rendered frame and keeps it filling the container.
///
/// The host assigns `previewView.frame = vc.view.bounds` and relies on an
/// autoresizing mask. That mask SCALES an existing frame, so if the bounds are
/// still `.zero` when it is assigned the view would stay zero-sized forever.
/// Laying out in `layoutSubviews` sidesteps that entirely.
final class GlassesPreviewView: UIView {
  let imageView: UIImageView = {
    let iv = UIImageView()
    // Fit, not fill. The glasses frame and the phone screen have different
    // aspect ratios, so filling crops the sides off - and the sides are
    // where a car at the kerb tends to be. Letterboxing keeps the whole
    // field of view the wearer actually has, which is also what the
    // detection pipeline sees.
    iv.contentMode = .scaleAspectFit
    iv.clipsToBounds = true
    return iv
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    addSubview(imageView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
  }
}

final class ExtentosFrameProvider: NSObject, FrameProvider {

  // MARK: - FrameProvider Protocol

  let previewView: UIView = GlassesPreviewView()
  weak var delegate: FrameProviderDelegate?
  let sourceType: CaptureSourceType = .metaGlasses
  private(set) var isRunning: Bool = false

  // MARK: - Configuration

  /// Resolution and frame rate the stream is requested at.
  ///
  /// The SDK's guidance is LOW/2fps for on-device ML and 7-15fps for preview,
  /// with 24-30fps draining the battery in roughly half an hour. This app
  /// tracks a moving vehicle while the user walks toward it, so the useful
  /// value is an open question - these are a starting point to measure from,
  /// not a tuned answer.
  ///
  /// On Meta hardware the requested resolution is a CEILING, not a guarantee:
  /// bandwidth drives an automatic quality ladder and the FIRST camera use in
  /// a session fixes the tier. Always read `frame.width`/`frame.height` rather
  /// than assuming what was asked for - `handleFrame` does.
  private let resolution: Resolution
  private let frameRate: Int

  // MARK: - Private

  private let glasses: ExtentosGlasses
  private var frameTask: Task<Void, Never>?

  private var bgraPool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0

  /// Built once - generating it per frame would dominate the conversion cost.
  private var conversionInfo = vImage_YpCbCrToARGB()
  private var conversionReady = false

  private var previewImageView: UIImageView {
    (previewView as! GlassesPreviewView).imageView
  }

  // MARK: - Init

  init(
    glasses: ExtentosGlasses,
    resolution: Resolution = .medium,
    frameRate: Int = 15
  ) {
    self.glasses = glasses
    self.resolution = resolution
    self.frameRate = frameRate
    super.init()
    conversionReady = Self.makeConversionInfo(&conversionInfo)
  }

  deinit {
    frameTask?.cancel()
  }

  // MARK: - FrameProvider Methods

  /// No-op: the SDK owns session setup, and ExtentosBootstrap owns the
  /// connection. Kept so the call site matches every other provider.
  func setupSession() {}

  func start() {
    guard !isRunning else { return }
    isRunning = true
    frameTask?.cancel()
    frameTask = Task { [weak self] in
      guard let self else { return }
      // Deliberately does NOT connect. ExtentosBootstrap owns the connection
      // lifecycle, and ConnectionClient documents that connect() on top of a
      // live session is not a supported path - reconnect() is.
      let config = VideoFrameConfig(
        resolution: self.resolution,
        frameRate: self.frameRate,
        codec: .raw,
        backpressure: .dropOldest
      )
      do {
        for try await frame in self.glasses.camera.videoFrames(config: config) {
          if Task.isCancelled { break }
          self.handleFrame(frame)
        }
      } catch {
        // Starting the stream while the wearer has the camera paused (temple
        // tap) throws here. A pause MID-stream is not an error: frames just
        // stop, and resume on the next tap.
        NSLog("[Extentos] video frame stream ended: \(error)")
      }
      await MainActor.run { self.isRunning = false }
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    frameTask?.cancel()
    frameTask = nil
  }

  // MARK: - Frame handling

  private func handleFrame(_ frame: VideoFrame) {
    let width = frame.width
    let height = frame.height
    guard width > 0, height > 0, conversionReady else { return }

    // A RAW frame is planar I420: Y (w*h) then U then V (each w/2 * h/2).
    // A mis-sized buffer is a hard error, never something to route into an
    // image decoder - it is still raw, so decoding can only fail confusingly.
    let expected = width * height * 3 / 2
    guard frame.buffer.count == expected else {
      NSLog(
        "[Extentos] dropping RAW frame with unexpected size: expected \(expected) bytes "
          + "for \(width)x\(height) I420, got \(frame.buffer.count)")
      return
    }

    guard let bgra = makeBGRABuffer(width: width, height: height) else { return }

    CVPixelBufferLockBaseAddress(bgra, [])
    let converted = convert(frame.buffer, width: width, height: height, into: bgra)
    let preview = converted ? makeCGImage(from: bgra, width: width, height: height) : nil
    CVPixelBufferUnlockBaseAddress(bgra, [])
    guard converted else { return }

    let decoded = DecodedFrame(buffer: bgra, preview: preview)
    Task { @MainActor [weak self] in
      guard let self, self.isRunning else { return }
      if let cg = decoded.preview {
        self.previewImageView.image = UIImage(cgImage: cg)
      }
      self.delegate?.processFrame(self, buffer: decoded.buffer, depthAt: { _ in nil })
    }
  }

  /// One decoded frame handed from the stream task to the main actor.
  ///
  /// `CVPixelBuffer` is not `Sendable`, but the transfer is safe by ownership:
  /// the buffer is vended fresh for this frame and the producing task never
  /// touches it again. The pool cannot recycle it while the consumer holds a
  /// reference.
  private struct DecodedFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let preview: CGImage?
  }

  // MARK: - Conversion

  /// Full-range BT.601. The SDK converts with BT.601 coefficients on both
  /// substrates, and the browser simulator's source is JPEG, which is full
  /// range. A wrong range shows as flat contrast, never as a black frame.
  private static func makeConversionInfo(_ info: inout vImage_YpCbCrToARGB) -> Bool {
    var pixelRange = vImage_YpCbCrPixelRange(
      Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255,
      YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
    let err = vImageConvert_YpCbCrToARGB_GenerateConversion(
      kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &pixelRange, &info,
      kvImage420Yp8_Cb8_Cr8, kvImageARGB8888, vImage_Flags(kvImageNoFlags))
    if err != kvImageNoError {
      NSLog("[Extentos] could not build the YpCbCr conversion: \(err)")
      return false
    }
    return true
  }

  /// The pipeline's contract: `FrameProviderDelegate` documents a BGRA buffer,
  /// and CameraViewModel hands it straight to Vision.
  private func convert(
    _ data: Data, width: Int, height: Int, into bgra: CVPixelBuffer
  ) -> Bool {
    guard let dest = CVPixelBufferGetBaseAddress(bgra) else { return false }
    let destStride = CVPixelBufferGetBytesPerRow(bgra)
    let chromaWidth = width / 2
    let chromaHeight = height / 2

    var result = false
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      let yPlane = UnsafeMutableRawPointer(mutating: base)
      let uPlane = yPlane.advanced(by: width * height)
      let vPlane = uPlane.advanced(by: chromaWidth * chromaHeight)

      var srcY = vImage_Buffer(
        data: yPlane, height: vImagePixelCount(height),
        width: vImagePixelCount(width), rowBytes: width)
      var srcU = vImage_Buffer(
        data: uPlane, height: vImagePixelCount(chromaHeight),
        width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
      var srcV = vImage_Buffer(
        data: vPlane, height: vImagePixelCount(chromaHeight),
        width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
      var dst = vImage_Buffer(
        data: dest, height: vImagePixelCount(height),
        width: vImagePixelCount(width), rowBytes: destStride)

      // vImage emits ARGB; the permute map reorders it into the BGRA the
      // pipeline expects: dest[B,G,R,A] <- src[3,2,1,0].
      let permute: [UInt8] = [3, 2, 1, 0]
      let err = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
        &srcY, &srcU, &srcV, &dst, &conversionInfo, permute, 255,
        vImage_Flags(kvImageDoNotTile))
      if err != kvImageNoError {
        NSLog("[Extentos] I420 -> BGRA conversion failed: \(err)")
        return
      }
      result = true
    }
    return result
  }

  private func makeCGImage(from bgra: CVPixelBuffer, width: Int, height: Int) -> CGImage? {
    guard let base = CVPixelBufferGetBaseAddress(bgra) else { return nil }
    let context = CGContext(
      data: base, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(bgra),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue)
    return context?.makeImage()
  }

  private func makeBGRABuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if bgraPool == nil || poolWidth != width || poolHeight != height {
      let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      ]
      var pool: CVPixelBufferPool?
      guard CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool) == kCVReturnSuccess
      else { return nil }
      bgraPool = pool
      poolWidth = width
      poolHeight = height
    }
    guard let bgraPool else { return nil }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, bgraPool, &buffer) == kCVReturnSuccess
    else { return nil }
    return buffer
  }
}
