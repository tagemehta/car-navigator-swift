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

  // Track last seen status per candidate so we only announce transitions.
  private var lastStatus: [UUID: MatchStatus] = [:]

  init(
    cache: AnnouncementCache,
    config: NavigationFeedbackConfig,
    speaker: SpeechOutput
  ) {
    self.cache = cache
    self.config = config
    self.speaker = speaker
  }

  /// Called once per frame with the latest candidate snapshot.
  func tick(candidates: [Candidate], timestamp: Date) {
    // Clutter suppression: prefer full matches, else partial, else everything.
    let full = candidates.filter { $0.matchStatus == .full }
    let partial = candidates.filter { $0.matchStatus == .partial }

    let active: [Candidate]
    if !full.isEmpty {
      active = full
    } else if !partial.isEmpty {
      active = partial
    } else {
      active = candidates
    }

    for candidate in active {
      handleCandidate(candidate, now: timestamp)
    }
  }

  // MARK: – Internal helpers
  private func handleCandidate(_ candidate: Candidate, now: Date) {
    // Build phrase.
    guard
      let phrase = MatchStatusSpeech.phrase(
        for: candidate.matchStatus,
        recognisedText: candidate.ocrText,
        detectedDescription: candidate.detectedDescription,
        rejectReason: candidate.rejectReason)
    else { return }

    // Waiting-specific global guard.
    switch candidate.matchStatus {
    case .waiting:
      if cache.hasSpokenWaiting { return }
      cache.hasSpokenWaiting = true
    case .partial, .full:
      cache.hasSpokenWaiting = false
    default:
      break
    }

    // Skip if status unchanged for candidate.
    if lastStatus[candidate.id] == candidate.matchStatus {
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
