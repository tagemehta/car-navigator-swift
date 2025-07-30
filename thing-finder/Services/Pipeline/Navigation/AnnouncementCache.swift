import Foundation

/// Keeps track of last-said phrases and waiting-phrase state.
/// A reference type so multiple controllers can share the same instance.
final class AnnouncementCache {
    /// Last phrase uttered globally.
    var lastGlobal: (phrase: String, time: Date)? = nil
    /// Last phrase uttered per candidate.
    var lastByCandidate: [UUID: (phrase: String, time: Date)] = [:]
    /// Whether the global "Waiting for verification" has already been said for the current epoch.
    var hasSpokenWaiting = false
}
