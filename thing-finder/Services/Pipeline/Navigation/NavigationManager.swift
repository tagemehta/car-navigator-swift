import CoreGraphics
import Foundation

/// Concrete façade that unifies speech phrases, direction words and beeps.
/// Call `tick(at:candidates:targetBox:distance:)` *once per video frame*.
final class FrameNavigationManager: NavigationSpeaker {
  private let settings: Settings
  private let announcer: NavAnnouncer
  private let dirController: DirectionSpeechController
  private let beepController: HapticBeepController

  init(
    settings: Settings,
    speaker: SpeechOutput,
    beeper: Beeper? = nil,
    hapticManager: HapticManagerProtocol? = nil
  ) {
    // Shared cache across controllers to coordinate phrase throttling.
    let cache = AnnouncementCache()
    self.settings = settings
    let config = NavigationFeedbackConfig(
      speechRepeatInterval: settings.speechRepeatInterval,
      directionChangeInterval: settings.speechChangeInterval,
      waitingPhraseCooldown: settings.waitingPhraseCooldown, retryPhraseCooldown: 6)
    // Single shared haptic manager for all controllers.
    let sharedHaptics = hapticManager ?? HapticManager(settings: settings)
    self.announcer = NavAnnouncer(
      cache: cache, config: config, speaker: speaker,
      hapticManager: sharedHaptics, settings: settings)
    self.dirController = DirectionSpeechController(
      cache: cache, config: config, speaker: speaker, settings: settings)
    let actualBeeper: SmoothBeeperProtocol =
      beeper as? SmoothBeeperProtocol ?? SmoothBeeper(settings: settings)
    self.beepController = HapticBeepController(
      beeper: actualBeeper, hapticManager: sharedHaptics, settings: settings)
  }

  // MARK: - NavigationSpeaker

  // MARK: - Tick
  func tick(
    at timestamp: Date,
    candidates: [Candidate],
    targetBox: CGRect?,
    distance: Double?
  ) {
    announcer.tick(candidates: candidates, timestamp: timestamp)
    dirController.tick(
      targetBox: targetBox, distance: distance, timestamp: timestamp)
    beepController.tick(targetBox: targetBox, timestamp: timestamp)
  }
}
