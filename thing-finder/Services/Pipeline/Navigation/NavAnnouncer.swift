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
    guard settings.enableSpeech else {
      return
    }

    // Clutter suppression: prefer full matches, else partial, else rejected cars.
    let full = candidates.filter { $0.matchStatus == .full }
    let partial = candidates.filter { $0.matchStatus == .partial }

    let active: [Candidate]
    if !full.isEmpty {
      active = full
    } else if !partial.isEmpty {
      active = partial
    } else if settings.announceRejected {
      active = candidates.filter { $0.matchStatus == .rejected }
    } else {
      active = []
    }

    // Process high-priority candidates (full/partial/rejected)
    for candidate in active {
      handleCandidate(candidate, now: timestamp)
    }

    // Handle waiting and retry messages independently of car announcements
    for candidate in candidates {
      handleWaitingAndRetry(candidate, now: timestamp)
    }
  }

  // MARK: – Internal helpers

  /// Handles waiting and retry messages, controlled by their own settings.
  private func handleWaitingAndRetry(_ candidate: Candidate, now: Date) {
    // Handle retry announcements for unknown status with retryable reason
    if settings.announceRetryMessages,
      candidate.matchStatus == .unknown,
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
      guard let retryPhrase = MatchStatusSpeech.retryPhrase(for: reason) else { return }

      // Speak and record
      speaker.speak(retryPhrase)
      cache.lastRetryTime = now
      lastRetryReasonSpoken[candidate.id] = reason
      return
    }

    // Handle waiting announcements
    if settings.announceWaitingMessages,
      candidate.matchStatus == .waiting
    {
      // Global waiting cooldown
      let elapsed = now.timeIntervalSince(cache.lastWaitingTime)
      if elapsed < config.waitingPhraseCooldown {
        return
      }

      // Skip if already announced waiting for this candidate
      if lastStatus[candidate.id] == .waiting {
        return
      }
      lastStatus[candidate.id] = .waiting

      speaker.speak("Waiting for verification")
      cache.lastWaitingTime = now
    }

    // Reset retry tracking when candidate is matched or hard rejected
    if candidate.isMatched || candidate.matchStatus == .rejected {
      lastRetryReasonSpoken[candidate.id] = nil
    }
  }

  /// Handles status announcements for full/partial/rejected candidates.
  private func handleCandidate(_ candidate: Candidate, now: Date) {
    // Build regular status phrase (excludes waiting/unknown which are handled separately)
    guard
      let phrase = MatchStatusSpeech.phrase(
        for: candidate.matchStatus, recognisedText: candidate.ocrText,
        detectedDescription: candidate.detectedDescription, rejectReason: candidate.rejectReason,
        normalizedXPosition: candidate.lastBoundingBox.midX, settings: settings,
        lastDirection: candidate.degrees)
    else { return }

    // Skip if status unchanged for candidate (except lost which can repeat with direction)
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
    cache.lastByCandidate[candidate.id] = (phrase, now)
    cache.lastGlobal = (phrase, now)
  }
}
