import Foundation
import CoreGraphics

// MARK: - Feedback Configuration
/// All timing and threshold constants for navigation feedback live here.
public struct NavigationFeedbackConfig {
    public var speechRepeatInterval: TimeInterval = 3
    public var directionChangeInterval: TimeInterval = 1
    public var waitingPhraseCooldown: TimeInterval = 10
    // Extend with more as needed
}

// MARK: - Small Output Protocols
public protocol SpeechOutput {
    func speak(_ text: String)
}

public protocol Beeper {
    /// Start a continuous tone at given `frequency` (Hz) and `volume` (0–1).
    func start(frequency: Double, volume: Float)
    /// Stop any ongoing tone.
    func stop()
}

// Main entry for frame-driven navigation speech / haptics.
public protocol NavigationSpeaker {
    func tick(at timestamp: Date,
              candidates: [Candidate],
              targetBox: CGRect?,
              distance: Double?)
}
