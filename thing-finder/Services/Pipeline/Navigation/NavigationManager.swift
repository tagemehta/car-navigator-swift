import CoreGraphics
import Foundation

/// Concrete façade that unifies speech phrases, direction words and beeps.
/// Call `tick(at:candidates:targetBox:distance:)` *once per video frame*.
///
/// Controller split:
///   • `PreMatchFeedbackController`    — handles all audio before a match exists
///     (session-start, heartbeat, earcon, rejection announcements).
///   • `NavAnnouncer`                  — announces partial / full / lost transitions.
///   • `DirectionSpeechController`     — "on your left / right" guidance (change-gated).
///   • `DistanceMilestoneController`   — "10 meters / 5 meters / almost there" (LiDAR only).
///   • `HapticBeepController`          — proximity beeps and haptic pulses.
final class FrameNavigationManager: NavigationSpeaker {
  private let settings: Settings
  private let preMatchController: PreMatchFeedbackController
  private let announcer: NavAnnouncer
  private let dirController: DirectionSpeechController
  private let milestoneController: DistanceMilestoneController
  private let beepController: HapticBeepController

  init(
    settings: Settings,
    targetDescription: String,
    speaker: SpeechOutput,
    beeper: Beeper? = nil,
    hapticManager: HapticManagerProtocol? = nil,
    earcon: EarconOutput? = nil
  ) {
    // Shared cache coordinates phrase throttling across all controllers.
    let cache = AnnouncementCache()
    self.settings = settings
    let config = NavigationFeedbackConfig(
      speechRepeatInterval: settings.speechRepeatInterval,
      directionChangeInterval: settings.speechChangeInterval,
      waitingPhraseCooldown: settings.waitingPhraseCooldown,
      retryPhraseCooldown: 6)

    let sharedHaptics = hapticManager ?? HapticManager(settings: settings)

    self.preMatchController = PreMatchFeedbackController(
      speaker: speaker,
      earcon: earcon ?? DetectionEarcon(),
      hapticManager: sharedHaptics,
      cache: cache,
      config: config,
      settings: settings,
      targetDescription: targetDescription)

    self.announcer = NavAnnouncer(
      cache: cache, config: config, speaker: speaker,
      hapticManager: sharedHaptics, settings: settings)

    self.dirController = DirectionSpeechController(
      cache: cache, config: config, speaker: speaker, settings: settings)

    self.milestoneController = DistanceMilestoneController(
      speaker: speaker, cache: cache, settings: settings, config: config)

    let actualBeeper: SmoothBeeperProtocol =
      beeper as? SmoothBeeperProtocol ?? SmoothBeeper(settings: settings)
    self.beepController = HapticBeepController(
      beeper: actualBeeper, hapticManager: sharedHaptics, settings: settings)
  }

  // MARK: - NavigationSpeaker

  func tick(
    at timestamp: Date,
    candidates: [Candidate],
    targetBox: CGRect?,
    distance: Double?
  ) {
    // Pre-match runs first so its cache updates are visible to other controllers.
    preMatchController.tick(candidates: candidates, timestamp: timestamp)
    announcer.tick(candidates: candidates, timestamp: timestamp)

    // Direction and milestones only provide value when a target is in frame.
    let hasActiveMatch = candidates.contains {
      $0.matchStatus == .partial || $0.matchStatus == .full
    }
    dirController.tick(
      targetBox: hasActiveMatch ? targetBox : nil,
      distance: distance,
      timestamp: timestamp)
    if hasActiveMatch {
      milestoneController.tick(distance: distance, timestamp: timestamp)
    }

    beepController.tick(targetBox: targetBox, distance: distance, timestamp: timestamp)
  }

  func reset() {
    preMatchController.reset()
    dirController.reset()
    milestoneController.reset()
  }
}
