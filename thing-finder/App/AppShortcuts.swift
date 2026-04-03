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

// MARK: - Find Paratransit Intent (with spoken description)

struct FindParatransitIntent: AppIntent {
  static var title: LocalizedStringResource = "Find My Paratransit"
  static var description = IntentDescription(
    "Start searching for your paratransit vehicle with a description")
  static var openAppWhenRun: Bool = true

  @Parameter(
    title: "Paratransit Description",
    description: "Describe your paratransit vehicle (e.g., white accesslink van)",
    requestValueDialog: "What does your paratransit vehicle look like?"
  )
  var paratransitDescription: String

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutNavigationState.shared.pendingParatransitDescription = paratransitDescription
    return .result()
  }
}

// MARK: - App Shortcuts Provider

struct ThingFinderShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: FindCarIntent(),
      phrases: [
        "Find my car with \(.applicationName)",
        "Find my ride with \(.applicationName)",
        "\(.applicationName) search",
      ],
      shortTitle: "Find My Car",
      systemImageName: "car.fill"
    )
    AppShortcut(
      intent: FindParatransitIntent(),
      phrases: [
        "Find my paratransit vehicle with \(.applicationName)",
        "Find my bus with \(.applicationName)",
        "\(.applicationName) Paratransit",
      ],
      shortTitle: "Find My Paratransit",
      systemImageName: "bus.fill"
    )
  }
}

// MARK: - Navigation State

@MainActor
@Observable
final class ShortcutNavigationState {
  static let shared = ShortcutNavigationState()

  var pendingCarDescription: String? = nil
  var pendingParatransitDescription: String? = nil
  private init() {}

  func consumePendingDescription() -> String? {
    let description = pendingCarDescription
    pendingCarDescription = nil
    return description
  }
  func consumePendingParatransitDescription() -> String? {
    let description = pendingParatransitDescription
    pendingParatransitDescription = nil
    return description
  }
}
