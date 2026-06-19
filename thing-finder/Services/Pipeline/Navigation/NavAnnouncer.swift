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
    // Clutter suppression: prefer full matches, else partial.
    // Rejected candidates are handled by PreMatchFeedbackController.
    let full = candidates.filter { $0.matchStatus == .full }
    let partial = candidates.filter { $0.matchStatus == .partial }
    let lost = candidates.filter { $0.matchStatus == .lost }

    var active: [Candidate]
    if !full.isEmpty {
      active = full
    } else if !partial.isEmpty {
      active = partial
    } else {
      active = []
    }
    // Lost candidates are always eligible (they were previously .full)
    active += lost

    // Announce status transitions (full / partial / lost)
    for candidate in active {
      handleCandidate(candidate, now: timestamp)
    }

    // Announce vehicle view changes (front/rear/side) for tracked candidates
    if settings.enableSpeech {
      for candidate in active {
        announceViewIfChanged(candidate)
      }
    }

    // Evict tracking state for candidates no longer in the snapshot
    let liveIDs = Set(candidates.map { $0.id })
    pruneStaleEntries(liveIDs: liveIDs)
  }

  // MARK: – Internal helpers

  /// Handles status announcements for full/partial/lost candidates.
  private func handleCandidate(_ candidate: Candidate, now: Date) {
    let previousStatus = lastStatus[candidate.id]

    // Build phrase — use the transition phrase when upgrading from partial to full
    // so the user hears "Plate confirmed" instead of a repeated "Found it".
    let phrase: String?
    if let prev = previousStatus,
      let transition = MatchStatusSpeech.transitionPhrase(
        from: prev, to: candidate.matchStatus, recognisedText: candidate.ocrText)
    {
      phrase = transition
    } else {
      phrase = MatchStatusSpeech.phrase(
        for: candidate.matchStatus,
        recognisedText: candidate.ocrText,
        lastDirection: candidate.degrees,
        currentHeading: compass.degrees)
    }

    guard let phrase else { return }

    // Skip if status unchanged for this candidate.
    // .lost is treated the same as any other status — the direction hint fires once
    // at the moment of transition and is then suppressed. Allowing it to repeat on
    // every frame causes the announcement to bounce between adjacent degree buckets
    // as the compass drifts (e.g. 89° → 90°), which is noisy and unhelpful.
    if previousStatus == candidate.matchStatus {
      return
    }
    lastStatus[candidate.id] = candidate.matchStatus

    // Trigger haptic feedback on status transitions (when haptics enabled)
    if settings.enableHaptics && previousStatus != candidate.matchStatus {
      switch candidate.matchStatus {
      case .full, .partial:
        hapticManager.playSuccess()
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
    case .front:
      phrase = String(localized: "Front view of car", comment: "Speech: vehicle viewed from front")
    case .rear:
      phrase = String(localized: "Rear view of car", comment: "Speech: vehicle viewed from rear")
    case .left:
      phrase = String(localized: "Left side of car", comment: "Speech: vehicle viewed from left")
    case .right:
      phrase = String(localized: "Right side of car", comment: "Speech: vehicle viewed from right")
    case .side:
      phrase = String(localized: "Side of car", comment: "Speech: vehicle viewed from side")
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
      lastViewAnnounced.removeValue(forKey: id)
      cache.lastByCandidate.removeValue(forKey: id)
    }
  }
}
