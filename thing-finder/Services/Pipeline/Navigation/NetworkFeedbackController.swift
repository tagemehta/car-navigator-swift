//  NetworkFeedbackController.swift
//  thing-finder
//
//  Notifies the user about connectivity problems that affect the search.
//  Runs independently of match state — connectivity issues are always worth
//  surfacing, even mid-navigation.
//
//  Responsibilities:
//    1. Pre-flight  — warns immediately if the device is already offline
//                     when a search session starts.
//    2. Outage      — "Connection lost" / "Connection restored" on hard
//                     connectivity transitions (Wi-Fi/cellular unreachable),
//                     each with a distinct haptic (error tap / success tap)
//                     so the transition is felt as well as heard.
//    3. Weak signal — "Weak signal" / recovery when requests are timing out
//                     or failing even though the device reports connectivity.
//
//  "Search paused" / "search resumed" are literal: `VerifierService` skips
//  its network-bound verification calls entirely while offline (see its
//  `networkMonitor` check), so no requests are wasted or retried into a dead
//  connection.

import Foundation

/// Distinguishes the haptic pattern used for a connectivity announcement.
private enum ConnectivityHaptic {
  case lost
  case restored
}

final class NetworkFeedbackController {

  // MARK: - Dependencies

  private let speaker: SpeechOutput
  private let hapticManager: HapticManagerProtocol
  private let cache: AnnouncementCache
  private let settings: Settings
  private let networkMonitor: NetworkMonitorProtocol
  private let apiHealthMonitor: APIHealthMonitorProtocol

  // MARK: - State

  /// Nil until the first tick, so the pre-flight check only fires once,
  /// at session start.
  private var lastKnownConnected: Bool?
  private var lastKnownDegraded = false

  // MARK: - Init

  init(
    speaker: SpeechOutput,
    hapticManager: HapticManagerProtocol,
    cache: AnnouncementCache,
    settings: Settings,
    networkMonitor: NetworkMonitorProtocol,
    apiHealthMonitor: APIHealthMonitorProtocol
  ) {
    self.speaker = speaker
    self.hapticManager = hapticManager
    self.cache = cache
    self.settings = settings
    self.networkMonitor = networkMonitor
    self.apiHealthMonitor = apiHealthMonitor
  }

  // MARK: - Public API

  /// Called once per frame from `FrameNavigationManager`.
  func tick(timestamp: Date) {
    checkConnectivity(timestamp: timestamp)
    checkDegradedSignal(timestamp: timestamp)
  }

  /// Resets all session state. Call when the user starts a new search.
  func reset() {
    lastKnownConnected = nil
    lastKnownDegraded = false
  }

  // MARK: - Hard connectivity (offline / restored)

  private func checkConnectivity(timestamp: Date) {
    let isConnected = networkMonitor.isConnected

    guard let wasConnected = lastKnownConnected else {
      // First tick of the session: pre-flight check.
      lastKnownConnected = isConnected
      if !isConnected {
        announce(
          String(
            localized: "No internet connection \u{2014} search may not work",
            comment: "Speech: device is offline when a search session starts"),
          haptic: .lost, timestamp: timestamp)
      }
      return
    }

    guard wasConnected != isConnected else { return }
    lastKnownConnected = isConnected

    if isConnected {
      announce(
        String(
          localized: "Connection restored \u{2014} search resumed",
          comment: "Speech: internet connectivity restored mid-search"),
        haptic: .restored, timestamp: timestamp)
    } else {
      announce(
        String(
          localized: "Connection lost \u{2014} search paused",
          comment: "Speech: internet connectivity lost mid-search"),
        haptic: .lost, timestamp: timestamp)
    }
  }

  // MARK: - Weak signal (connected, but requests are failing)

  private func checkDegradedSignal(timestamp: Date) {
    let isDegraded = apiHealthMonitor.isDegraded

    // A hard outage already announces its own, clearer message — don't pile on.
    guard networkMonitor.isConnected else { return }

    guard isDegraded != lastKnownDegraded else { return }
    lastKnownDegraded = isDegraded

    if isDegraded {
      announce(
        String(
          localized: "Weak signal \u{2014} verification may be delayed",
          comment: "Speech: connected, but requests are failing or timing out"),
        haptic: nil, timestamp: timestamp)
    } else {
      announce(
        String(
          localized: "Signal improved",
          comment: "Speech: weak-signal condition has cleared"),
        haptic: nil, timestamp: timestamp)
    }
  }

  // MARK: - Helpers

  private func announce(_ phrase: String, haptic: ConnectivityHaptic?, timestamp: Date) {
    // Connectivity status is safety-relevant for every user, so unlike other
    // categories of feedback it isn't gated by its own toggle — only by the
    // master speech/haptics switches.
    if settings.enableHaptics {
      switch haptic {
      case .lost: hapticManager.playFailure()
      case .restored: hapticManager.playSuccess()
      case nil: break
      }
    }
    guard settings.enableSpeech else { return }
    speaker.speak(phrase)
    cache.lastGlobal = (phrase: phrase, time: timestamp)
  }
}
