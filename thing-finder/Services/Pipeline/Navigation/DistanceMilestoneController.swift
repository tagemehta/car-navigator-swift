import Foundation

/// Announces distance milestones as the user approaches a matched vehicle.
///
/// Design:
///   • Milestones fire at 10 m / 5 m / 2 m / 1 m.
///   • Each threshold fires once per approach.
///   • If the user backs away more than `hysteresis` beyond a threshold, that
///     threshold re-arms and will fire again on the next approach.
///   • At most one milestone fires per tick; the farthest uncrossed threshold
///     fires first so the user hears them in natural order.
///   • Silently inactive when `distance` is nil (non-LiDAR device) or when
///     speech is disabled.
///
/// Owned by `FrameNavigationManager`; only called when an active match exists.
final class DistanceMilestoneController {

  // MARK: - Types

  struct Milestone {
    let threshold: Double   // metres
    let label: String
  }

  // MARK: - Configuration

  private let milestones: [Milestone] = [
    Milestone(threshold: 10, label: String(localized: "10 meters", comment: "Speech: distance milestone")),
    Milestone(threshold: 5, label: String(localized: "5 meters", comment: "Speech: distance milestone")),
    Milestone(threshold: 2, label: String(localized: "2 meters", comment: "Speech: distance milestone")),
    Milestone(threshold: 1, label: String(localized: "almost there", comment: "Speech: very close to vehicle")),
  ]

  /// Distance beyond a threshold the user must move away before it re-arms.
  private let hysteresis: Double = 1.5

  // MARK: - Dependencies

  private let speaker: SpeechOutput
  private let cache: AnnouncementCache
  private let settings: Settings
  private let config: NavigationFeedbackConfig

  // MARK: - State

  /// Thresholds (in metres) that have already been crossed this approach.
  private var crossedThresholds: Set<Double> = []

  // MARK: - Init

  init(
    speaker: SpeechOutput,
    cache: AnnouncementCache,
    settings: Settings,
    config: NavigationFeedbackConfig
  ) {
    self.speaker = speaker
    self.cache = cache
    self.settings = settings
    self.config = config
  }

  // MARK: - Public API

  /// Call once per frame when an active match exists.
  /// `distance` is the LiDAR depth estimate in metres; pass `nil` on non-LiDAR devices.
  func tick(distance: Double?, timestamp: Date) {
    guard settings.enableSpeech, let dist = distance else { return }

    // Re-arm thresholds the user has backed away from (with hysteresis).
    for milestone in milestones {
      if crossedThresholds.contains(milestone.threshold),
        dist > milestone.threshold + hysteresis
      {
        crossedThresholds.remove(milestone.threshold)
      }
    }

    // Fire the farthest uncrossed milestone the user is now within.
    // milestones[] is ordered 10 → 1 so iteration gives us far-first.
    for milestone in milestones {
      guard !crossedThresholds.contains(milestone.threshold) else { continue }
      guard dist <= milestone.threshold else { continue }

      // Back off if another controller just spoke to avoid talking over it.
      if let g = cache.lastGlobal,
        timestamp.timeIntervalSince(g.time) < config.milestoneCooldown
      {
        return
      }

      crossedThresholds.insert(milestone.threshold)
      speaker.speak(milestone.label)
      cache.lastGlobal = (milestone.label, timestamp)
      break  // At most one milestone per tick
    }
  }

  /// Reset all state.  Call when the user starts a new search so milestones
  /// fire again at the correct distances for the next car.
  func reset() {
    crossedThresholds.removeAll()
  }
}
