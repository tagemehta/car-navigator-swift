import CoreGraphics
import Foundation

/// Emits direction words with distance based on the bounding box centre X normalised to 0–1.
final class DirectionSpeechController {
  private let config: NavigationFeedbackConfig
  private let speaker: SpeechOutput
  private var lastDirection: Direction = .center
  private var timeLastSpoken: Date = .distantPast
  private let settings: Settings

  init(config: NavigationFeedbackConfig, speaker: SpeechOutput, settings: Settings) {
    self.config = config
    self.speaker = speaker
    self.settings = settings
  }

  /// Pass `nil` when there is no active target against which to provide direction.
  func tick(targetBox: CGRect?, distance: Double?, timestamp: Date) {
    guard let box = targetBox, settings.enableSpeech else { return }
    let newDir = settings.getDirection(normalizedX: box.midX)
    let elapsed = timestamp.timeIntervalSince(timeLastSpoken)

    var distanceText: String = ""
    if let dist = distance {
      let roundedDistance = Int(round(dist))
      distanceText = "\(roundedDistance) meters"

    }

    let announcement: String
    if newDir == lastDirection {
      if elapsed > config.speechRepeatInterval {
        announcement = "Still \(newDir.rawValue), \(distanceText)"
      } else {
        return  // Skip announcement
      }
    } else {
      if elapsed > config.directionChangeInterval {
        announcement =
          distanceText.isEmpty ? newDir.rawValue : "\(newDir.rawValue), \(distanceText)"
        lastDirection = newDir
      } else {
        return  // Skip announcement
      }
    }

    speak(text: announcement)
  }

  private func speak(text: String) {
    timeLastSpoken = Date()
    speaker.speak(text)
  }
}
