import Foundation
import SwiftUI

enum SearchMode: String, CaseIterable, Identifiable, Codable {
  case uberFinder = "Uber Finder"
  case objectFinder = "Object Finder"

  var id: String { self.rawValue }

  var description: String {
    switch self {
    case .uberFinder:
      return "Find your vehicle with a simple description"
    case .objectFinder:
      return "Search for specific objects from a list of 80+ classes"
    }
  }

  var placeholder: String {
    switch self {
    case .uberFinder:
      return "Describe your vehicle (e.g., 'blue Toyota Prius with license plate ABC123')"
    case .objectFinder:
      return "Add details about the object (e.g., 'red backpack with white stripes')"
    }
  }
}
