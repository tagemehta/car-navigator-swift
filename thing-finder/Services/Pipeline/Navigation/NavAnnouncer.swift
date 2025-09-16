import CoreGraphics
import Foundation

/// Lightweight value object returned when `NavAnnouncer` decides a phrase
/// should be spoken this frame.
struct Announcement {
  let phrase: String
}

/// Pure phrase-selection engine.  It owns no side-effects except calling the
/// injected `SpeechOutput` implementation.
final class NavAnnouncer {
  private let cache: AnnouncementCache
  private let config: NavigationFeedbackConfig
  private let speaker: SpeechOutput
  private let settings: Settings

  // Track last seen status per candidate so we only announce transitions.
  private var lastStatus: [UUID: MatchStatus] = [:]

  // Track last announced retry reason per candidate to avoid repetition
  private var lastRetryReasonSpoken: [UUID: RejectReason] = [:]

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

  /// Called once per frame with the latest candidate snapshot.
  func tick(candidates: [Candidate], timestamp: Date) {
    // Clutter suppression: prefer full matches, else partial, else everything.
    guard settings.enableSpeech else {
      return
    }
    let full = candidates.filter { $0.matchStatus == .full }
    let partial = candidates.filter { $0.matchStatus == .partial }

    let active: [Candidate]
    if !full.isEmpty {
      active = full
    } else if !partial.isEmpty {
      active = partial
    } else if settings.announceRejected {
      active = candidates
    } else {
      return
    }

    for candidate in active {
      handleCandidate(candidate, now: timestamp)
    }
  }

  // MARK: – Internal helpers
  private func handleCandidate(_ candidate: Candidate, now: Date) {
    // Check for retry announcements first
    if candidate.matchStatus == .unknown,
      let reason = candidate.rejectReason,
      reason.isRetryable,
      lastRetryReasonSpoken[candidate.id] != reason
    {

      // Global retry cooldown
      let elapsedRetry = now.timeIntervalSince(cache.lastRetryTime)
      if elapsedRetry < config.retryPhraseCooldown {
        return
      }
      // Create retry phrase
      let retryPhrase: String
      switch reason {
      case .unclearImage: retryPhrase = "Picture too blurry, trying again"
      case .insufficientInfo: retryPhrase = "Need a better view, retrying"
      case .lowConfidence: retryPhrase = "Not sure yet, taking another shot"
      case .apiError: retryPhrase = "Detection error, retrying"
      case .licensePlateNotVisible: retryPhrase = "Can't see the plate, retrying"
      case .ambiguous: retryPhrase = "Results unclear, retrying"
      default: return  // No speech for non-retryable reasons
      }

      // Speak and record
      speaker.speak(retryPhrase)
      cache.lastRetryTime = now
      lastRetryReasonSpoken[candidate.id] = reason
      return  // Skip normal status phrase this frame
    }

    // Reset retry tracking when candidate is matched or hard rejected
    if candidate.isMatched || candidate.matchStatus == .rejected {
      lastRetryReasonSpoken[candidate.id] = nil
    }

    // Build regular status phrase
    guard
      let phrase = MatchStatusSpeech.phrase(
        for: candidate.matchStatus, recognisedText: candidate.ocrText,
        detectedDescription: candidate.detectedDescription, rejectReason: candidate.rejectReason,
        normalizedXPosition: candidate.lastBoundingBox.midX, settings: settings, lastDirection: candidate.degrees)
    else { return }

    // Waiting-specific global cooldown guard.
    if candidate.matchStatus == .waiting {
      let elapsed = now.timeIntervalSince(cache.lastWaitingTime)
      if elapsed < config.waitingPhraseCooldown {
        return  // skip if spoken too recently
      }
    }

    // Skip if status unchanged for candidate or its a lost candidate.
    if lastStatus[candidate.id] == candidate.matchStatus && candidate.matchStatus != .lost {
      return
    }
    lastStatus[candidate.id] = candidate.matchStatus

    // Global repeat suppression.
    if let g = cache.lastGlobal,
      g.phrase == phrase,
      Date().timeIntervalSince(g.time) < config.speechRepeatInterval
    {
      return
    }
    // Per-candidate suppression.
    if let last = cache.lastByCandidate[candidate.id],
      last.phrase == phrase,
      Date().timeIntervalSince(last.time) < config.speechRepeatInterval
    {
      return
    }

    // Speak and record.
    speaker.speak(phrase)
    if candidate.matchStatus == .waiting {
      cache.lastWaitingTime = now
    }
    cache.lastByCandidate[candidate.id] = (phrase, now)
    cache.lastGlobal = (phrase, now)
  }
}
