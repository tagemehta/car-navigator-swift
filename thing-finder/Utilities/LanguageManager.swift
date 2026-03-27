import Foundation
import SwiftUI

/// Manages runtime language override for both SwiftUI views and `String(localized:)` calls.
///
/// When a non-system language is chosen, this class:
/// 1. Sets `UserDefaults.standard["AppleLanguages"]` so `String(localized:)` picks the right catalog
/// 2. Provides a `Locale` for the SwiftUI `.environment(\.locale, …)` modifier
///
/// Changes take effect on next app launch for `String(localized:)` in non-SwiftUI contexts;
/// SwiftUI views update immediately via the environment locale.
enum LanguageManager {

  /// Call once on app startup (before any UI) and again whenever the setting changes.
  static func applyLanguage(_ language: SupportedLanguage) {
    if language == .system {
      // Remove override so the OS language is used
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    } else {
      UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
    UserDefaults.standard.synchronize()
  }

  /// Returns a `Locale` matching the user's chosen language for SwiftUI environment injection.
  static func locale(for language: SupportedLanguage) -> Locale {
    switch language {
    case .system:
      return .current
    case .english:
      return Locale(identifier: "en")
    case .spanish:
      return Locale(identifier: "es")
    }
  }
}
