import Foundation

/// Keeps track of last-said phrases.
/// A reference type so multiple controllers can share the same instance.
final class AnnouncementCache {
  /// Last phrase uttered globally.
  var lastGlobal: (phrase: String, time: Date)? = nil
  /// Last phrase uttered per candidate.
  var lastByCandidate: [UUID: (phrase: String, time: Date)] = [:]
}
