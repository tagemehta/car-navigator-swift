import Foundation

/// Keeps track of last-said phrases.
/// A reference type so multiple controllers can share the same instance.
final class AnnouncementCache {
  /// Last phrase uttered globally.
  var lastGlobal: (phrase: String, time: Date)? = nil
  /// Last phrase uttered per candidate.
  var lastByCandidate: [UUID: (phrase: String, time: Date)] = [:]
  /// Frame timestamp of a connectivity announcement that must not be cut off.
  /// `Speaker.speak` cancels whatever is currently playing, so controllers
  /// running later in the same frame defer their own phrase by a frame.
  var priorityFrame: Date? = nil

  /// True when a connectivity announcement already claimed this frame.
  func isFramePreempted(_ timestamp: Date) -> Bool {
    priorityFrame == timestamp
  }
}
