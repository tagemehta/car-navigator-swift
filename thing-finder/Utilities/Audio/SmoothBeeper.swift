import AVFoundation
import Foundation
import SwiftUI

/// A simplified, beat-preserving beeper.
///
/// Design goals (matches project principles):
/// • Safe from bugs   – one timer, no busy-loop, race-free reschedule logic.
/// • Easy to understand – play → schedule next, only five core vars.
/// • Ready for change   – all timing contained in `scheduleNextBeep()`.
final class SmoothBeeper: SmoothBeeperProtocol {
  // Settings for configurable parameters
  private let settings: Settings
  // MARK: – Public configuration
  private let alpha: Double = 0.2  // Smoothing factor for EMA
  private let minInterval: TimeInterval = 0.1

  // MARK: – Private state
  private var player: AVAudioPlayer?
  private var timer: Timer?
  private var lastBeepTime: Date = .distantPast
  private var currentInterval: TimeInterval = 0.5
  private var targetInterval: TimeInterval = 0.5
  private var smoothedInterval: TimeInterval = 1.0
  private var volume: Float = 0.5
  private var isBeeping = false
  private var wasPlayingBeforePause = false

  // MARK: – Init / Deinit
  init(settings: Settings = Settings()) {
    self.settings = settings
    // Prepare click sound once.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("beep.wav")
    self.soundURL = url
    configureAudioSession()
    generateClickSound()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAppDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePauseAllAudio),
      name: AudioControl.pauseAllNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleResumeAllAudio),
      name: AudioControl.resumeAllNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    stop()
    //    #if os(iOS)
    //    try? AVAudioSession.sharedInstance().setActive(false)
    //    #endif
  }

  // MARK: – Beeper protocol
  func start(frequency: Double, volume: Float = 1.0) {
    // Frequency is mapped to interval: higher frequency beeps faster.
    let interval = max(minInterval, 1.0 / frequency)
    updateVolume(to: Double(volume))
    start(interval: interval)
  }

  // MARK: – Public API
  /// Dynamically adjust the output volume (0.0 – 1.0).
  func updateVolume(to newVolume: Double) {
    let clamped = max(0.0, min(1.0, newVolume))
    player?.volume = Float(clamped)
  }
  /// Begin beeping at the supplied interval.
  func start(interval: TimeInterval) {
    stop()  // Clean slate
    // Smooth the interval using exponential moving average based on settings
    targetInterval = max(minInterval, interval)
    smoothedInterval =
      settings.smoothingAlpha * targetInterval + (1 - settings.smoothingAlpha) * smoothedInterval
    lastBeepTime = Date()
    playBeep()  // Play immediately
    scheduleNextBeep(after: smoothedInterval)
  }

  /// Stop any ongoing beeps.
  func stop() {
    timer?.invalidate()
    timer = nil
    player?.stop()
  }

  /// Request the beeper to move toward a new interval.  If `smoothly==false` the
  /// change is immediate; otherwise an exponential-moving-average is applied and
  /// the next beat is rescheduled so the rhythm stays continuous.
  func updateInterval(to newInterval: TimeInterval, smoothly: Bool = true) {
    let safe = max(minInterval, newInterval)
    targetInterval = safe
    if !smoothly {
      currentInterval = safe
      rescheduleTimer()
      return
    }
    // EMA smoothing.
    currentInterval = (1 - alpha) * currentInterval + alpha * targetInterval
    rescheduleTimer()
  }

  // MARK: – Private – Timing helpers
  private func rescheduleTimer() {
    guard timer != nil else { return }  // Nothing scheduled yet.
    let elapsed = Date().timeIntervalSince(lastBeepTime)
    let remaining = max(0.0, currentInterval - elapsed)
    scheduleNextBeep(after: remaining)
  }

  private func scheduleNextBeep(after delay: TimeInterval) {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      self?.handleTimerFire()
    }
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }

  private func handleTimerFire() {
    playBeep()
    scheduleNextBeep(after: currentInterval)  // schedule following beat
  }

  private func playBeep() {
    guard let p = player else { return }
    p.currentTime = 0
    _ = p.play()
    lastBeepTime = Date()
  }

  // MARK: – Private – Audio setup
  private let soundURL: URL

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }

  @objc private func handleAppDidEnterBackground() {
    wasPlayingBeforePause = (timer != nil)
    stop()
  }

  @objc private func handleWillEnterForeground() {
    if wasPlayingBeforePause {
      start(interval: targetInterval)
    }
  }

  @objc private func handlePauseAllAudio() {
    wasPlayingBeforePause = (timer != nil)
    stop()
  }

  @objc private func handleResumeAllAudio() {
    if wasPlayingBeforePause {
      wasPlayingBeforePause = false
      start(interval: targetInterval)
    }
  }

  private func generateClickSound() {
    guard !FileManager.default.fileExists(atPath: soundURL.path) else {
      player = try? AVAudioPlayer(contentsOf: soundURL)
      player?.prepareToPlay()
      return
    }
    let sampleRate: Double = 44100
    let duration: Double = 0.03
    let frequency: Double = 1000
    let numSamples = Int(duration * sampleRate)
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: sampleRate,
      channels: 1,
      interleaved: false)!
    let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(numSamples))!
    buffer.frameLength = AVAudioFrameCount(numSamples)
    let channel = buffer.floatChannelData![0]
    for i in 0..<numSamples {
      let t = Double(i) / sampleRate
      let envelope = sin(.pi * Double(i) / Double(numSamples))
      channel[i] = Float(sin(2 * .pi * frequency * t) * envelope)
    }
    if let file = try? AVAudioFile(forWriting: soundURL, settings: format.settings) {
      try? file.write(from: buffer)
    }
    player = try? AVAudioPlayer(contentsOf: soundURL)
    player?.prepareToPlay()
  }
}
