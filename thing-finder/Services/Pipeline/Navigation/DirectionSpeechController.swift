import CoreGraphics
import Foundation

/// Emits direction words when the bounding-box centre X (normalised 0–1)
/// crosses a category boundary (left / center / right).
///
/// Design: change-gated only.
///   • Fires on the first frame where a match exists.
///   • Fires again only when the direction category changes.
///   • Never repeats the same category — beeps and milestones carry the rest.
///   • Uses `directionChangeInterval` as a debounce to absorb brief oscillation.
final class DirectionSpeechController {
  private let cache: AnnouncementCache
  private let config: NavigationFeedbackConfig
  private let speaker: SpeechOutput
  private let settings: Settings

  /// Last category that was actually spoken (nil = nothing spoken yet this session).
  private var lastSpokenDirection: Direction? = nil

  init(
    cache: AnnouncementCache,
    config: NavigationFeedbackConfig,
    speaker: SpeechOutput,
    settings: Settings
  ) {
    self.cache = cache
    self.config = config
    self.speaker = speaker
    self.settings = settings
  }

  /// Pass `nil` when there is no active target against which to provide direction.
  func tick(targetBox: CGRect?, distance: Double?, timestamp: Date) {
    guard let box = targetBox, settings.enableSpeech else { return }
    let newDir = settings.getDirection(normalizedX: box.midX)

    // Only speak on a direction category change (or the very first announcement).
    guard newDir != lastSpokenDirection else { return }

    // Debounce: don't speak if another controller just spoke within the window.
    // This also prevents rapid oscillation between adjacent categories.
    if let g = cache.lastGlobal,
      timestamp.timeIntervalSince(g.time) < config.directionChangeInterval
    {
      // Don't update lastSpokenDirection here — we'll retry on the next frame
      // once the cooldown window has elapsed.
      return
    }

    lastSpokenDirection = newDir
    let phrase = newDir.localizedName
    speaker.speak(phrase)
    cache.lastGlobal = (phrase, timestamp)
  }

  /// Reset session state.  Call when starting a new search so the first direction
  /// is always announced even if the same category is seen again.
  func reset() {
    lastSpokenDirection = nil
  }
}
