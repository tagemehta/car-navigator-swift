import Foundation
import CoreGraphics

/// Concrete façade that unifies speech phrases, direction words and beeps.
/// Call `tick(at:candidates:targetBox:distance:)` *once per video frame*.
final class FrameNavigationManager: NavigationSpeaker {
    private let settings: Settings
    private let announcer: NavAnnouncer
    private let dirController: DirectionSpeechController
    private let beepController: HapticBeepController

    init(settings: Settings,
         speaker: SpeechOutput,
         beeper: Beeper? = nil,
         config: NavigationFeedbackConfig = NavigationFeedbackConfig()) {
        // Shared cache across controllers to coordinate phrase throttling.
        let cache = AnnouncementCache()
        self.settings = settings
        self.announcer = NavAnnouncer(cache: cache, config: config, speaker: speaker)
        self.dirController = DirectionSpeechController(config: config, speaker: speaker)
        let actualBeeper = beeper ?? SmoothBeeper(settings: settings)
        self.beepController = HapticBeepController(beeper: actualBeeper, settings: settings)
    }

    // MARK: - NavigationSpeaker
    
    // MARK: - Tick
    func tick(at timestamp: Date,
              candidates: [Candidate],
              targetBox: CGRect?,
              distance: Double?) {
        announcer.tick(candidates: candidates, timestamp: timestamp)
        dirController.tick(targetBox: targetBox, distance: distance, timestamp: timestamp, settings: settings)
        beepController.tick(targetBox: targetBox, timestamp: timestamp)
    }
}
