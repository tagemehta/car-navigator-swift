import AppIntents
import SwiftUI

// MARK: - Find Car Intent (with spoken description)

struct FindCarIntent: AppIntent {
  static var title: LocalizedStringResource = "Find My Car"
  static var description = IntentDescription("Start searching for your car with a description")
  static var openAppWhenRun: Bool = true

  @Parameter(
    title: "Car Description",
    description: "Describe your car (e.g., white Toyota Camry)",
    requestValueDialog: "What does your car look like?"
  )
  var carDescription: String

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutNavigationState.shared.pendingCarDescription = carDescription
    return .result()
  }
}

// MARK: - App Shortcuts Provider

struct ThingFinderShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: FindCarIntent(),
      phrases: [
        "CurbToCar with \(.applicationName)",
        "Find my car with \(.applicationName)",
        "Find my ride with \(.applicationName)",
      ],
      shortTitle: "Find My Car",
      systemImageName: "car.fill"
    )
  }
}

// MARK: - Navigation State

@MainActor
@Observable
final class ShortcutNavigationState {
  static let shared = ShortcutNavigationState()

  var pendingCarDescription: String? = nil

  private init() {}

  func consumePendingDescription() -> String? {
    let description = pendingCarDescription
    pendingCarDescription = nil
    return description
  }
}
