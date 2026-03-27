import Foundation
import SwiftUI

enum SearchMode: String, CaseIterable, Identifiable, Codable {
  case uberFinder = "Uber Finder"
  case objectFinder = "Object Finder"

  var id: String { self.rawValue }

  var description: String {
    switch self {
    case .uberFinder:
      return String(
        localized: "Find your vehicle with a simple description",
        comment: "SearchMode: Uber Finder description")
    case .objectFinder:
      return String(
        localized: "Search for specific objects from a list of 80+ classes",
        comment: "SearchMode: Object Finder description")
    }
  }

  var placeholder: String {
    switch self {
    case .uberFinder:
      return String(
        localized: "Describe your vehicle (e.g., 'blue Toyota Prius with license plate ABC123')",
        comment: "SearchMode: Uber Finder placeholder")
    case .objectFinder:
      return String(
        localized: "Add details about the object (e.g., 'red backpack with white stripes')",
        comment: "SearchMode: Object Finder placeholder")
    }
  }
}
