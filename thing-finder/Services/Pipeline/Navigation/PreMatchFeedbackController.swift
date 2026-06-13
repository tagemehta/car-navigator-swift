//  PreMatchFeedbackController.swift
//  thing-finder
//
//  Owns all audio feedback during the pre-match phase (no candidate is yet
//  partial or full). Goes dormant once a match exists so it doesn't fight
//  NavAnnouncer or the beep controller.
//
//  Responsibilities:
//    1. Session-start  — "Searching for [targetDescription]…" once per search.
//    2. Heartbeat      — "Still looking…" every ~20 s while no candidates exist.
//    3. Earcon         — soft tone + light haptic tap ~0.3 s after any new car
//                        enters the pipeline (deduped for candidate lifetime).
//    4. Rejections     — "Not yours — [desc]" per candidate, throttled;
//                        degrades to "Several cars nearby, still looking" in
//                        high-density mode (> N rejections in a rolling window).

import Foundation

final class PreMatchFeedbackController {

  // MARK: - Dependencies

  private let speaker: SpeechOutput
  private let earcon: EarconOutput
  private let hapticManager: HapticManagerProtocol
  private let cache: AnnouncementCache
  private let config: NavigationFeedbackConfig
  private let settings: Settings
  private let targetDescription: String

  // MARK: - Session state

  private var sessionStarted = false

  // MARK: - Earcon deduplication

  /// Lifetime set — never pruned. Prevents re-firing for candidates that
  /// leave and re-enter the frame (e.g., momentary occlusion).
  private var seenCandidates: Set<UUID> = []
  /// First-seen timestamps for the stability gate; pruned when candidate leaves.
  private var candidateFirstSeen: [UUID: Date] = [:]

  // MARK: - Heartbeat

  private var lastHeartbeatTime: Date = .distantPast

  // MARK: - Rejection tracking

  /// Candidates that have already received a rejection announcement.
  private var announcedRejections: Set<UUID> = []
  /// Timestamps of recent individual rejection announcements (for density).
  private var recentRejectionTimes: [Date] = []
  /// Last time the grouped "several cars nearby" message was spoken.
  private var lastGroupedRejectionTime: Date = .distantPast

  // MARK: - Init

  init(
    speaker: SpeechOutput,
    earcon: EarconOutput,
    hapticManager: HapticManagerProtocol,
    cache: AnnouncementCache,
    config: NavigationFeedbackConfig,
    settings: Settings,
    targetDescription: String
  ) {
    self.speaker = speaker
    self.earcon = earcon
    self.hapticManager = hapticManager
    self.cache = cache
    self.config = config
    self.settings = settings
    self.targetDescription = targetDescription
  }

  // MARK: - Public API

  /// Called once per frame from `FrameNavigationManager`.
  func tick(candidates: [Candidate], timestamp: Date) {
    guard settings.enableSpeech else { return }

    // Session-start fires exactly once per search, regardless of match state.
    if !sessionStarted {
      let phrase = String(
        format: NSLocalizedString(
          "Searching for %@",
          comment: "Speech: session start — announces what the user is searching for"),
        targetDescription)
      speak(phrase, at: timestamp)
      sessionStarted = true
      lastHeartbeatTime = timestamp
    }

    let hasMatch = candidates.contains { $0.matchStatus == .partial || $0.matchStatus == .full }

    // Earcon fires for any new-enough candidate before a match is confirmed.
    // Once beeps are running (match found) earcons are suppressed to avoid confusion.
    if !hasMatch {
      tickEarcons(candidates: candidates, timestamp: timestamp)
      tickHeartbeat(candidates: candidates, timestamp: timestamp)
      tickRejections(candidates: candidates, timestamp: timestamp)
    }

    // Prune first-seen times for candidates that left the snapshot.
    // (seenCandidates is intentionally never pruned — lifetime deduplication.)
    let liveIDs = Set(candidates.map { $0.id })
    for id in candidateFirstSeen.keys where !liveIDs.contains(id) {
      candidateFirstSeen.removeValue(forKey: id)
    }
  }

  /// Resets all session state. Call when the user starts a new search.
  func reset() {
    sessionStarted = false
    seenCandidates.removeAll()
    candidateFirstSeen.removeAll()
    lastHeartbeatTime = .distantPast
    announcedRejections.removeAll()
    recentRejectionTimes.removeAll()
    lastGroupedRejectionTime = .distantPast
  }

  // MARK: - Earcon

  private func tickEarcons(candidates: [Candidate], timestamp: Date) {
    guard settings.enableBeeps else { return }

    for candidate in candidates {
      let id = candidate.id
      guard !seenCandidates.contains(id) else { continue }

      // Record when we first saw this candidate.
      if candidateFirstSeen[id] == nil {
        candidateFirstSeen[id] = timestamp
      }
      guard let firstSeen = candidateFirstSeen[id] else { continue }

      // Stability gate: ignore transient detections under the threshold.
      guard timestamp.timeIntervalSince(firstSeen) >= config.earconStabilityGate else { continue }

      // Commit: mark as seen for the lifetime of this session.
      seenCandidates.insert(id)
      earcon.play()
      if settings.enableHaptics {
        hapticManager.playDetection()
      }
    }
  }

  // MARK: - Heartbeat

  private func tickHeartbeat(candidates: [Candidate], timestamp: Date) {
    guard settings.announceWaitingMessages else { return }

    // Heartbeat only fires when there are no candidates at all.
    guard candidates.isEmpty else { return }

    // Don't interrupt other recent speech.
    if let lastGlobal = cache.lastGlobal,
      timestamp.timeIntervalSince(lastGlobal.time) < 10
    {
      return
    }

    guard timestamp.timeIntervalSince(lastHeartbeatTime) >= config.scanningHeartbeatInterval
    else { return }

    let phrase = String(
      localized: "Still looking\u{2026}",
      comment: "Speech: scanning heartbeat when no candidates are detected")
    speak(phrase, at: timestamp)
    lastHeartbeatTime = timestamp
  }

  // MARK: - Rejections

  private func tickRejections(candidates: [Candidate], timestamp: Date) {
    guard settings.announceRejected else { return }

    // Prune stale timestamps outside the density window.
    recentRejectionTimes = recentRejectionTimes.filter {
      timestamp.timeIntervalSince($0) < config.rejectionDensityWindow
    }

    let rejected = candidates.filter { $0.matchStatus == .rejected }
    for candidate in rejected {
      let id = candidate.id
      guard !announcedRejections.contains(id) else { continue }

      // Global cooldown between any two rejection announcements.
      // Don't mark the candidate yet — if suppressed it must remain eligible.
      if let lastGlobal = cache.lastGlobal,
        timestamp.timeIntervalSince(lastGlobal.time) < config.rejectionCooldown
      {
        continue
      }

      if recentRejectionTimes.count >= config.rejectionDensityLimit {
        // High-density mode: collapse into a single grouped phrase.
        // Don't mark the candidate yet — if the grouped cooldown suppresses it,
        // it must remain eligible on the next tick.
        guard timestamp.timeIntervalSince(lastGroupedRejectionTime) > 10 else { continue }
        announcedRejections.insert(id)
        let phrase = String(
          localized: "Several cars nearby, still looking",
          comment: "Speech: many rejections in a short window")
        speak(phrase, at: timestamp)
        lastGroupedRejectionTime = timestamp
      } else {
        // Individual rejection.
        let phrase: String
        if let desc = candidate.detectedDescription {
          phrase = String(
            format: NSLocalizedString(
              "Not yours \u{2014} %@",
              comment: "Speech: rejected car with description"),
            desc)
        } else {
          phrase = String(
            localized: "Not yours",
            comment: "Speech: rejected car, no description available")
        }
        announcedRejections.insert(id)
        speak(phrase, at: timestamp)
        recentRejectionTimes.append(timestamp)
      }

      // Only one rejection announcement per tick to avoid speech pile-up.
      break
    }
  }

  // MARK: - Helpers

  private func speak(_ phrase: String, at timestamp: Date) {
    speaker.speak(phrase)
    cache.lastGlobal = (phrase: phrase, time: timestamp)
  }
}
