//  MockSettings.swift
//  thing-finderTests
//
//  Test helper to create Settings instances with specific values for testing.

import CoreGraphics
import Foundation

@testable import thing_finder

/// Helper to create a Settings instance configured for testing.
/// Since Settings uses @AppStorage, we configure it directly rather than subclassing.
enum TestSettings {

  /// Creates a Settings instance with default test values.
  /// Note: This modifies UserDefaults, so tests should reset after use.
  static func makeDefault() -> Settings {
    let settings = Settings()
    settings.enableSpeech = true
    settings.enableBeeps = true
    settings.announceRejected = false
    settings.speechRepeatInterval = 6.0
    settings.speechChangeInterval = 4.0
    settings.waitingPhraseCooldown = 10.0
    settings.directionLeftThreshold = 0.33
    settings.directionRightThreshold = 0.66
    return settings
  }

  /// Creates a Settings instance with speech disabled.
  static func makeSpeechDisabled() -> Settings {
    let settings = makeDefault()
    settings.enableSpeech = false
    return settings
  }

  /// Creates a Settings instance with beeps disabled.
  static func makeBeepsDisabled() -> Settings {
    let settings = makeDefault()
    settings.enableBeeps = false
    return settings
  }

  /// Creates a Settings instance that announces rejected candidates.
  static func makeWithRejectedAnnouncements() -> Settings {
    let settings = makeDefault()
    settings.announceRejected = true
    return settings
  }

  /// Creates a Settings instance with short cooldowns for faster testing.
  static func makeWithShortCooldowns() -> Settings {
    let settings = makeDefault()
    settings.speechRepeatInterval = 0.1
    settings.speechChangeInterval = 0.1
    settings.waitingPhraseCooldown = 0.1
    return settings
  }
}
