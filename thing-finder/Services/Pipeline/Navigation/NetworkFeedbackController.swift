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
//                     connectivity transitions (Wi-Fi/cellular unreachable).
//    3. Weak signal — "Weak signal" / recovery when requests are timing out
//                     or failing even though the device reports connectivity.

import Foundation

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
          haptic: true, timestamp: timestamp)
      }
      return
    }

    guard wasConnected != isConnected else { return }
    lastKnownConnected = isConnected

    if isConnected {
      announce(
        String(
          localized: "Connection restored",
          comment: "Speech: internet connectivity restored mid-search"),
        haptic: false, timestamp: timestamp)
    } else {
      announce(
        String(
          localized: "Connection lost \u{2014} search paused",
          comment: "Speech: internet connectivity lost mid-search"),
        haptic: true, timestamp: timestamp)
    }
  }

  // MARK: - Weak signal (connected, but requests are failing)

  private func checkDegradedSignal(timestamp: Date) {
    let isDegraded = apiHealthMonitor.isDegraded
    guard isDegraded != lastKnownDegraded else { return }
    lastKnownDegraded = isDegraded

    // A hard outage already announces its own, clearer message — don't pile on.
    guard networkMonitor.isConnected else { return }

    if isDegraded {
      announce(
        String(
          localized: "Weak signal \u{2014} verification may be delayed",
          comment: "Speech: connected, but requests are failing or timing out"),
        haptic: false, timestamp: timestamp)
    } else {
      announce(
        String(
          localized: "Signal improved",
          comment: "Speech: weak-signal condition has cleared"),
        haptic: false, timestamp: timestamp)
    }
  }

  // MARK: - Helpers

  private func announce(_ phrase: String, haptic: Bool, timestamp: Date) {
    // Connectivity status is safety-relevant for every user, so unlike other
    // categories of feedback it isn't gated by its own toggle — only by the
    // master speech/haptics switches.
    if haptic && settings.enableHaptics {
      hapticManager.playFailure()
    }
    guard settings.enableSpeech else { return }
    speaker.speak(phrase)
    cache.lastGlobal = (phrase: phrase, time: timestamp)
  }
}
