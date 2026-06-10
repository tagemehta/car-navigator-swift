import Foundation

/// Announces distance milestones as the user approaches a matched vehicle.
///
/// Design:
///   • Milestones fire at 10 m / 5 m / 2 m / 1 m ("almost there").
///   • When the user crosses multiple thresholds at once (e.g. jumps from 12 m
///     to 3 m), all skipped thresholds are silently marked as done and only
///     the *closest* one is announced — the most actionable information.
///   • If the user backs away more than `hysteresis` beyond a crossed threshold,
///     it re-arms and fires again on the next approach.
///   • Thresholds are not marked until the announcement actually plays —
///     if the global cooldown suppresses speech, all pending milestones
///     remain eligible for the next tick.
///   • Silently inactive when `distance` is nil (non-LiDAR device) or speech is off.
///   • Distance labels are locale-aware (feet in US, metres elsewhere).
///
/// Owned by `FrameNavigationManager`; only called when an active match exists.
final class DistanceMilestoneController {

  // MARK: - Types

  struct Milestone {
    let threshold: Double  // metres
    /// If set, overrides the formatter output (e.g. "almost there" at 1 m).
    let labelOverride: String?

    init(threshold: Double, labelOverride: String? = nil) {
      self.threshold = threshold
      self.labelOverride = labelOverride
    }

    func label(using formatter: MeasurementFormatter) -> String {
      if let override = labelOverride { return override }
      return formatter.string(from: Measurement(value: threshold, unit: UnitLength.meters))
    }
  }

  // MARK: - Configuration

  /// Ordered farthest → closest so iteration naturally processes far milestones
  /// before near ones when scanning for eligibility.
  private let milestones: [Milestone] = [
    Milestone(threshold: 10),
    Milestone(threshold: 5),
    Milestone(threshold: 2),
    Milestone(
      threshold: 1,
      labelOverride: String(
        localized: "almost there", comment: "Speech: very close to vehicle")),
  ]

  /// Distance (m) beyond a crossed threshold the user must move before it re-arms.
  private let hysteresis: Double = 1.5

  // MARK: - Dependencies

  private let speaker: SpeechOutput
  private let cache: AnnouncementCache
  private let settings: Settings
  private let config: NavigationFeedbackConfig
  // KNOWN ISSUE — mixes languages in non-English locales (inherited limitation).
  private let distanceFormatter: MeasurementFormatter

  // MARK: - State

  /// Thresholds (m) that have already been crossed and announced this approach.
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

    let f = MeasurementFormatter()
    f.unitOptions = .naturalScale
    f.unitStyle = .long
    f.numberFormatter.maximumFractionDigits = 0
    self.distanceFormatter = f
  }

  // MARK: - Public API

  /// Call once per frame when an active match exists.
  /// `distance` is the LiDAR depth estimate in metres; pass `nil` on non-LiDAR devices.
  func tick(distance: Double?, timestamp: Date) {
    guard settings.enableSpeech, let dist = distance else { return }

    // Re-arm thresholds where the user has backed away with sufficient clearance.
    for milestone in milestones {
      if crossedThresholds.contains(milestone.threshold),
        dist > milestone.threshold + hysteresis
      {
        crossedThresholds.remove(milestone.threshold)
      }
    }

    // Collect all newly-eligible (uncrossed, within range) thresholds.
    // Iterate closest-first (reversed) so the first match is the one to announce.
    var toAnnounce: Milestone? = nil
    var toMark: [Double] = []

    for milestone in milestones.reversed() {  // 1 → 2 → 5 → 10
      guard !crossedThresholds.contains(milestone.threshold) else { continue }
      guard dist <= milestone.threshold else { continue }
      toMark.append(milestone.threshold)
      if toAnnounce == nil { toAnnounce = milestone }  // closest wins
    }

    guard let milestone = toAnnounce else { return }

    // Back off if another controller just spoke; don't mark thresholds yet
    // so they remain eligible on the next tick.
    if let g = cache.lastGlobal,
      timestamp.timeIntervalSince(g.time) < config.milestoneCooldown
    {
      return
    }

    // Commit: mark all newly-entered thresholds as done (closest + any skipped farther ones).
    for threshold in toMark { crossedThresholds.insert(threshold) }

    let label = milestone.label(using: distanceFormatter)
    speaker.speak(label)
    cache.lastGlobal = (label, timestamp)
  }

  /// Reset all state. Call when starting a new search so milestones re-fire
  /// at the correct distances for the next vehicle.
  func reset() {
    crossedThresholds.removeAll()
  }
}
