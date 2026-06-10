import CoreGraphics
import Foundation

// MARK: - Feedback Configuration
/// All timing and threshold constants for navigation feedback live here.
public struct NavigationFeedbackConfig {
  // MARK: Post-match (NavAnnouncer / DirectionSpeechController)
  public var speechRepeatInterval: TimeInterval = 6
  public var directionChangeInterval: TimeInterval = 4
  /// Retained for backwards-compatibility; no longer read by NavAnnouncer.
  public var waitingPhraseCooldown: TimeInterval = 10
  /// Retained for backwards-compatibility; no longer read by NavAnnouncer.
  public var retryPhraseCooldown: TimeInterval = 8

  // MARK: Pre-match (PreMatchFeedbackController)
  /// Seconds a candidate must be stable before the earcon fires.
  public var earconStabilityGate: TimeInterval = 0.3
  /// Seconds between "Still looking…" heartbeat announcements.
  public var scanningHeartbeatInterval: TimeInterval = 20
  /// Minimum seconds between consecutive individual rejection announcements.
  public var rejectionCooldown: TimeInterval = 3.5
  /// Rolling window (seconds) used to measure rejection density.
  public var rejectionDensityWindow: TimeInterval = 30
  /// Number of rejections within `rejectionDensityWindow` that triggers grouped mode.
  public var rejectionDensityLimit: Int = 3

  // MARK: Post-match milestones (DistanceMilestoneController)
  /// Minimum gap (seconds) between a milestone announcement and any other speech.
  public var milestoneCooldown: TimeInterval = 1.0

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
/// A beeper that supports smooth interval changes.
public protocol SmoothBeeperProtocol: Beeper {
  /// Begin beeping at the supplied interval.
  func start(interval: TimeInterval)
  /// Request the beeper to move toward a new interval.
  func updateInterval(to newInterval: TimeInterval, smoothly: Bool)
}

// Main entry for frame-driven navigation speech / haptics.
public protocol NavigationSpeaker {
  func tick(
    at timestamp: Date,
    candidates: [Candidate],
    targetBox: CGRect?,
    distance: Double?)
  /// Reset session state (session-start announcement, earcon deduplication, etc.).
  /// Call whenever the user starts a new search.
  func reset()
}
