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
  private let hapticManager: HapticManagerProtocol
  private let compass: CompassProvider
  private let settings: Settings

  // Track last seen status per candidate so we only announce transitions.
  private var lastStatus: [UUID: MatchStatus] = [:]

  // Track last announced retry reason per candidate to avoid repetition
  private var lastRetryReasonSpoken: [UUID: RejectReason] = [:]

  // Track last announced vehicle view per candidate (announce once, re-announce on change)
  private var lastViewAnnounced: [UUID: Candidate.VehicleView] = [:]

  init(
    cache: AnnouncementCache,
    config: NavigationFeedbackConfig,
    speaker: SpeechOutput,
    hapticManager: HapticManagerProtocol,
    compass: CompassProvider = CompassHeading.shared,
    settings: Settings
  ) {
    self.cache = cache
    self.config = config
    self.speaker = speaker
    self.hapticManager = hapticManager
    self.compass = compass
    self.settings = settings
  }

  /// Called once per frame with the latest candidate snapshot.
  func tick(candidates: [Candidate], timestamp: Date) {
    // Clutter suppression: prefer full matches, else partial, else rejected/lost.
    let full = candidates.filter { $0.matchStatus == .full }
    let partial = candidates.filter { $0.matchStatus == .partial }
    let lost = candidates.filter { $0.matchStatus == .lost }

    var active: [Candidate]
    if !full.isEmpty {
      active = full
    } else if !partial.isEmpty {
      active = partial
    } else if settings.announceRejected {
      active = candidates.filter { $0.matchStatus == .rejected }
    } else {
      active = []
    }
    // Lost candidates are always eligible (they were previously .full)
    active += lost

    // Process high-priority candidates (full/partial/rejected/lost)
    for candidate in active {
      handleCandidate(candidate, now: timestamp)
    }

    // Announce vehicle view changes (front/rear/side) for tracked candidates
    if settings.enableSpeech {
      for candidate in active {
        announceViewIfChanged(candidate)
      }
    }

    // Handle waiting and retry messages independently of car announcements (speech only)
    if settings.enableSpeech {
      for candidate in candidates {
        handleWaitingAndRetry(candidate, now: timestamp)
      }
    }

    // Evict tracking state for candidates no longer in the snapshot
    let liveIDs = Set(candidates.map { $0.id })
    pruneStaleEntries(liveIDs: liveIDs)
  }

  // MARK: – Internal helpers

  /// Handles waiting and retry messages, controlled by their own settings.
  private func handleWaitingAndRetry(_ candidate: Candidate, now: Date) {
    // Reset retry tracking when candidate is matched or hard rejected.
    // This must run unconditionally — before any early returns.
    if candidate.isMatched || candidate.matchStatus == .rejected {
      lastRetryReasonSpoken[candidate.id] = nil
    }

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
  }

  /// Handles status announcements for full/partial/rejected/lost candidates.
  private func handleCandidate(_ candidate: Candidate, now: Date) {
    // Build regular status phrase (excludes waiting/unknown which are handled separately)
    guard
      let phrase = MatchStatusSpeech.phrase(
        for: candidate.matchStatus, recognisedText: candidate.ocrText,
        detectedDescription: candidate.detectedDescription, rejectReason: candidate.rejectReason,
        normalizedXPosition: candidate.lastBoundingBox.midX, settings: settings,
        lastDirection: candidate.degrees,
        currentHeading: compass.degrees)
    else { return }

    // Skip if status unchanged for candidate (except lost which can repeat with direction)
    let previousStatus = lastStatus[candidate.id]
    if previousStatus == candidate.matchStatus && candidate.matchStatus != .lost {
      return
    }
    lastStatus[candidate.id] = candidate.matchStatus

    // Trigger haptic feedback on status transitions (when haptics enabled)
    if settings.enableHaptics && previousStatus != candidate.matchStatus {
      switch candidate.matchStatus {
      case .full, .partial:
        hapticManager.playSuccess()
      case .rejected:
        hapticManager.playFailure()
      default:
        break
      }
    }

    // Skip speech if disabled, but haptics already fired above
    guard settings.enableSpeech else { return }

    // Global repeat suppression (uses passed-in timestamp for testability).
    if let g = cache.lastGlobal,
      g.phrase == phrase,
      now.timeIntervalSince(g.time) < config.speechRepeatInterval
    {
      return
    }
    // Per-candidate suppression.
    if let last = cache.lastByCandidate[candidate.id],
      last.phrase == phrase,
      now.timeIntervalSince(last.time) < config.speechRepeatInterval
    {
      return
    }

    // Speak and record.
    speaker.speak(phrase)
    cache.lastByCandidate[candidate.id] = (phrase, now)
    cache.lastGlobal = (phrase, now)
  }

  // MARK: - Vehicle View Announcements

  /// Announce the vehicle view (front, rear, side) once per candidate,
  /// and again only if it changes.
  private func announceViewIfChanged(_ candidate: Candidate) {
    let view = candidate.view
    guard view != .unknown else { return }

    if lastViewAnnounced[candidate.id] == view { return }
    lastViewAnnounced[candidate.id] = view

    let phrase: String
    switch view {
    case .front: phrase = "Front view of car"
    case .rear: phrase = "Rear view of car"
    case .left: phrase = "Left side of car"
    case .right: phrase = "Right side of car"
    case .side: phrase = "Side of car"
    case .unknown: return
    }

    speaker.speak(phrase)
    cache.lastGlobal = (phrase, Date())
  }

  // MARK: - Eviction

  /// Remove tracking state for candidates that are no longer in the snapshot.
  private func pruneStaleEntries(liveIDs: Set<UUID>) {
    for id in lastStatus.keys where !liveIDs.contains(id) {
      lastStatus.removeValue(forKey: id)
      lastRetryReasonSpoken.removeValue(forKey: id)
      lastViewAnnounced.removeValue(forKey: id)
      cache.lastByCandidate.removeValue(forKey: id)
    }
  }
}
