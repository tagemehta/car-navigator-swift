import Foundation

/// Keeps track of last-said phrases and waiting-phrase state.
/// A reference type so multiple controllers can share the same instance.
final class AnnouncementCache {
    /// Last phrase uttered globally.
    var lastGlobal: (phrase: String, time: Date)? = nil
    /// Last phrase uttered per candidate.
    var lastByCandidate: [UUID: (phrase: String, time: Date)] = [:]
    /// Timestamp the global "Waiting for verification" phrase was last spoken.
    var lastWaitingTime: Date = .distantPast
    /// Timestamp the last retry phrase (e.g. "need a better view") was spoken globally.
    var lastRetryTime: Date = .distantPast
}
