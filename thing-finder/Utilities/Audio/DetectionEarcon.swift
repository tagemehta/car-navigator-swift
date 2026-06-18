//  DetectionEarcon.swift
//  thing-finder
//
//  Plays a brief soft tone when a new car enters the verification pipeline,
//  signalling "I see something — checking it." Distinct from the navigation beeps
//  (which signal a match) and from speech (which carries semantic content).

import AVFoundation
import Foundation

/// Protocol for one-shot audio earcon playback.
public protocol EarconOutput {
  func play()
}

/// Concrete earcon: 200 ms, 800 Hz, Hann-windowed sine wave.
///
/// Lower and shorter than the 1 kHz navigation beep so the user can
/// distinguish "new car detected" from "heading toward your car."
final class DetectionEarcon: EarconOutput {
  private var player: AVAudioPlayer?
  private let soundURL: URL
  private var isMuted = false

  init() {
    soundURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("detection_earcon.wav")
    generateSoundIfNeeded()
    NotificationCenter.default.addObserver(
      self, selector: #selector(handlePauseAll),
      name: AudioControl.pauseAllNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleResumeAll),
      name: AudioControl.resumeAllNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func play() {
    guard !isMuted, let player else { return }
    player.currentTime = 0
    player.play()
  }

  // MARK: - Notifications

  @objc private func handlePauseAll() { isMuted = true }
  @objc private func handleResumeAll() { isMuted = false }

  // MARK: - Sound generation

  private func generateSoundIfNeeded() {
    // Reuse the cached file across launches to avoid regenerating every session.
    if FileManager.default.fileExists(atPath: soundURL.path) {
      player = try? AVAudioPlayer(contentsOf: soundURL)
      player?.prepareToPlay()
      return
    }

    let sampleRate: Double = 44100
    let duration: Double = 0.2      // 200 ms
    let frequency: Double = 800     // 800 Hz — below the 1 kHz nav beep
    let numSamples = Int(duration * sampleRate)

    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate, channels: 1, interleaved: false),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples))
    else { return }
    buffer.frameLength = AVAudioFrameCount(numSamples)

    let channel = buffer.floatChannelData![0]
    for i in 0..<numSamples {
      let t = Double(i) / sampleRate
      // Hann window: smooth fade-in/out eliminates clicks.
      let envelope = 0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(numSamples)))
      channel[i] = Float(sin(2.0 * .pi * frequency * t) * envelope * 0.7)
    }

    if let file = try? AVAudioFile(forWriting: soundURL, settings: format.settings) {
      try? file.write(from: buffer)
    }
    player = try? AVAudioPlayer(contentsOf: soundURL)
    player?.prepareToPlay()
  }
}
