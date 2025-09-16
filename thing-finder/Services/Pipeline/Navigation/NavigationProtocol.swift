import CoreGraphics
import Foundation

// MARK: - Feedback Configuration
/// All timing and threshold constants for navigation feedback live here.
public struct NavigationFeedbackConfig {
  public var speechRepeatInterval: TimeInterval = 6
  public var directionChangeInterval: TimeInterval = 4
  public var waitingPhraseCooldown: TimeInterval = 10
  public var retryPhraseCooldown: TimeInterval = 8

  init(
    speechRepeatInterval: TimeInterval,
    directionChangeInterval: TimeInterval,
    waitingPhraseCooldown: TimeInterval,
    retryPhraseCooldown: TimeInterval
  ) {
    self.speechRepeatInterval = speechRepeatInterval
    self.directionChangeInterval = directionChangeInterval
    self.waitingPhraseCooldown = waitingPhraseCooldown
    self.retryPhraseCooldown = retryPhraseCooldown
  }
  init() {
    self.speechRepeatInterval = 6
    self.directionChangeInterval = 4
    self.waitingPhraseCooldown = 10
    self.retryPhraseCooldown = 8
  }
  // Extend with more as needed
}

// MARK: - Small Output Protocols
public protocol SpeechOutput {
  func speak(_ text: String)
}

public protocol Beeper {
  /// Start a continuous tone at given `frequency` (Hz) and `volume` (0–1).
  func start(frequency: Double, volume: Float)
  /// Stop any ongoing tone.
  func stop()
}

// Main entry for frame-driven navigation speech / haptics.
public protocol NavigationSpeaker {
  func tick(
    at timestamp: Date,
    candidates: [Candidate],
    targetBox: CGRect?,
    distance: Double?)
}
