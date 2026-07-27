import SwiftUI

/// The top-level tabs of the app. Used to drive `TabView` selection
/// programmatically (e.g. deep-linking from one tab to another).
enum AppTab: Hashable {
  case find
  case settings
}

/// App-wide navigation coordinator.
///
/// Lets views in one tab route the user to a destination in another tab.
/// Currently used so the Meta glasses connection overlay (in the Find tab)
/// can send the user to the Meta Glasses section of Settings.
@MainActor
final class AppRouter: ObservableObject {
  /// The currently selected tab.
  @Published var selectedTab: AppTab = .find

  /// Set when something requests the Meta Glasses settings section. `SettingsView`
  /// observes this to reveal (advanced settings) and scroll to that section, then
  /// resets it back to `false`.
  @Published var pendingScrollToMetaGlasses: Bool = false

  /// Route the user to the Meta Glasses section of Settings.
  func openMetaGlassesSettings() {
    selectedTab = .settings
    pendingScrollToMetaGlasses = true
  }
}

/// Stable identifiers for scroll anchors inside Settings.
enum SettingsAnchor: Hashable {
  case metaGlasses
}
