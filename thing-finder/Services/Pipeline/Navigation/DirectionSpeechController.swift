import CoreGraphics
import Foundation

/// Emits direction words with distance based on the bounding box centre X normalised to 0–1.
final class DirectionSpeechController {
  private let cache: AnnouncementCache
  private let config: NavigationFeedbackConfig
  private let speaker: SpeechOutput
  private var lastDirection: Direction = .center
  private var timeLastSpoken: Date = .distantPast
  private let settings: Settings
  private let distanceFormatter: MeasurementFormatter

  init(
    cache: AnnouncementCache, config: NavigationFeedbackConfig, speaker: SpeechOutput,
    settings: Settings
  ) {
    self.cache = cache
    self.config = config
    self.speaker = speaker
    self.settings = settings

    // KNOWN ISSUE - mixes languages in non English locales
    let formatter = MeasurementFormatter()
    formatter.unitOptions = .naturalScale
    formatter.unitStyle = .long
    formatter.numberFormatter.maximumFractionDigits = 0
    self.distanceFormatter = formatter
  }

  /// Pass `nil` when there is no active target against which to provide direction.
  func tick(targetBox: CGRect?, distance: Double?, timestamp: Date) {
    guard let box = targetBox, settings.enableSpeech else { return }
    let newDir = settings.getDirection(normalizedX: box.midX)
    let elapsed = timestamp.timeIntervalSince(timeLastSpoken)

    var distanceText: String = ""
    if let dist = distance {
      let measurement = Measurement(value: dist, unit: UnitLength.meters)
      distanceText = distanceFormatter.string(from: measurement)
    }

    let announcement: String
    if newDir == lastDirection {
      if elapsed > config.speechRepeatInterval {
        if distanceText.isEmpty {
          announcement = String(
            localized: "Still \(newDir.localizedName)",
            comment: "Speech: direction unchanged, no distance")
        } else {
          announcement = String(
            format: NSLocalizedString(
              "Still %@, %@",
              comment: "Speech: direction unchanged, with distance"),
            newDir.localizedName, distanceText)
        }
      } else {
        return  // Skip announcement
      }
    } else {
      if elapsed > config.directionChangeInterval {
        if distanceText.isEmpty {
          announcement = newDir.localizedName
        } else {
          announcement = String(
            format: NSLocalizedString(
              "%@, %@",
              comment: "Speech: new direction with distance"),
            newDir.localizedName, distanceText)
        }
        lastDirection = newDir
      } else {
        return  // Skip announcement
      }
    }

    speak(text: announcement, at: timestamp)
  }

  private func speak(text: String, at timestamp: Date) {
    // Check if another controller just spoke (avoid talking over NavAnnouncer)
    if let g = cache.lastGlobal,
      timestamp.timeIntervalSince(g.time) < config.directionChangeInterval
    {
      return
    }
    timeLastSpoken = timestamp
    speaker.speak(text)
    cache.lastGlobal = (text, timestamp)
  }
}
