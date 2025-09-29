import ARKit
import Combine
import Foundation
import SwiftUI

/// Direction enum for navigation guidance
enum Direction: String {
  case left = "on your left"
  case right = "on your right"
  case center = "straight ahead"
}

/// Settings model that stores user preferences for the navigation experience.
/// Uses @AppStorage for persistence and provides defaults matching the original implementation.
public class Settings: ObservableObject {
  // MARK: - Navigation Settings
  /// Speech rate (-1.0 to 1.0, where 0 is normal)
  @AppStorage("speech_rate") var speechRate: Double = 0.5
  
  /// Minimum interval between beeps when target is centered (seconds)
  @AppStorage("beep_interval_min") var beepIntervalMin: Double = 0.1

  /// Maximum interval between beeps when target is at edge (seconds)
  @AppStorage("beep_interval_max") var beepIntervalMax: Double = 1.0

  /// Threshold for left direction (normalized x < this value)
  @AppStorage("direction_left_threshold") var directionLeftThreshold: Double = 0.33

  /// Threshold for right direction (normalized x > this value)
  @AppStorage("direction_right_threshold") var directionRightThreshold: Double = 0.66

  /// Minimum time between repeating the same direction (seconds)
  @AppStorage("speech_repeat_interval") var speechRepeatInterval: Double = 4.0

  /// Minimum time between announcing direction changes (seconds)
  @AppStorage("speech_change_interval") var speechChangeInterval: Double = 2.0

  /// Cooldown time for waiting phrases (seconds)
  @AppStorage("waiting_phrase_cooldown") var waitingPhraseCooldown: Double = 10.0

  // MARK: - Distance Feedback Settings

  /// Minimum distance for volume mapping (meters)
  @AppStorage("distance_min") var distanceMin: Double = 0.2

  /// Maximum distance for volume mapping (meters)
  @AppStorage("distance_max") var distanceMax: Double = 10.0

  /// Minimum volume level (0.0-1.0)
  @AppStorage("volume_min") var volumeMin: Double = 0.2

  /// Maximum volume level (0.0-1.0)
  @AppStorage("volume_max") var volumeMax: Double = 1.0

  /// Type of distance-to-volume curve
  @AppStorage("volume_curve") var volumeCurve: VolumeCurve = .linear

  // MARK: - Camera Settings

  /// Whether to use AR mode (false = Default/AVFoundation, true = ARKit)
  @AppStorage("use_ar_mode") var useARMode: Bool = false

  /// Whether the device has LiDAR for distance estimation
  var hasLiDAR: Bool {
    return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
  }

  /// Recommended camera mode based on device capabilities
  var recommendedMode: CaptureSourceType {
    return hasLiDAR ? .avFoundation : .arKit
  }

  // MARK: - Detection Settings

  /// Confidence threshold for detection (0.0-1.0)
  @AppStorage("confidence_threshold") var confidenceThreshold: Double = 0.4

  /// Delay between LLM verifications (seconds)
  @AppStorage("verification_cooldown") var verificationCooldown: Double = 10.0

  /// Number of frames to keep target before declaring it expired
  @AppStorage("target_lifetime") var targetLifetime: Int = 700

  /// Number of consecutive lost frames before giving up tracking
  @AppStorage("max_lost_frames") var maxLostFrames: Int = 4

  // MARK: - Tracking Drift Thresholds

  // MARK: - Feedback Mode Settings

  /// Enable audio feedback (beeps)
  @AppStorage("enable_beeps") var enableBeeps: Bool = true

  /// Enable haptic feedback
  @AppStorage("enable_haptics") var enableHaptics: Bool = false

  /// Enable speech feedback
  @AppStorage("enable_speech") var enableSpeech: Bool = true

  /// Allow navigation cues before plate confirm (partial match)
  @AppStorage("allow_partial_nav") var allowPartialNavigation: Bool = true

  /// Announce all detected cars (rejected candidates as well)
  @AppStorage("announce_rejected") var announceRejected: Bool = true

  /// Smoothing factor for exponential moving average (0.0-1.0)
  @AppStorage("smoothing_alpha") var smoothingAlpha: Double = 0.2

  /// Enable developer mode with additional settings
  @AppStorage("developer_mode") var developerMode: Bool = false
  
  /// Enable debug overlay with verification messages
  @AppStorage("debug_overlay_enabled") var debugOverlayEnabled: Bool = false
}

/// Volume curve types for distance mapping
enum VolumeCurve: String, CaseIterable, Identifiable {
  case linear = "Linear"
  case logarithmic = "Logarithmic"
  case quadratic = "Quadratic"

  var id: String { self.rawValue }
}

// MARK: - Settings Extensions

extension Settings {
  /// Maps distance to volume based on settings
  func mapDistanceToVolume(_ distanceMeters: Double) -> Double {
    let clampedDistance = max(distanceMin, min(distanceMax, distanceMeters))
    let normalizedDistance: Double

    if distanceMax - distanceMin <= 0 {
      normalizedDistance = 0
    } else {
      normalizedDistance = 1.0 - ((clampedDistance - distanceMin) / (distanceMax - distanceMin))
    }

    let mappedValue: Double
    switch volumeCurve {
    case .linear:
      mappedValue = normalizedDistance
    case .logarithmic:
      mappedValue = normalizedDistance <= 0 ? 0 : log(1 + 9 * normalizedDistance) / log(10)
    case .quadratic:
      mappedValue = normalizedDistance * normalizedDistance
    }

    return volumeMin + (volumeMax - volumeMin) * mappedValue
  }

  /// Returns the direction based on normalized x position
  func getDirection(normalizedX: CGFloat) -> Direction {
    if normalizedX < directionLeftThreshold {
      return .left
    } else if normalizedX > directionRightThreshold {
      return .right
    } else {
      return .center
    }
  }

  /// Calculates beep interval based on distance from center
  func calculateBeepInterval(distanceFromCenter: Double) -> TimeInterval {
    // Normalize to 0.0-1.0 where 1.0 is centered
    let normalizedDistance = 1.0 - min(1.0, distanceFromCenter * 2)

    // Apply curve based on settings
    let factor: Double
    switch volumeCurve {
    case .linear:
      factor = normalizedDistance
    case .logarithmic:
      factor = normalizedDistance <= 0 ? 0 : log(1 + 9 * normalizedDistance) / log(10)
    case .quadratic:
      factor = normalizedDistance * normalizedDistance
    }

    // Map to interval range
    return beepIntervalMax - (beepIntervalMax - beepIntervalMin) * factor
  }

  /// Reset all settings to their default values. This is a temporary fix until we can find a better way to reset settings.
  func resetToDefaults() {
    // Set each property to its default value
    // Navigation Settings
    beepIntervalMin = 0.1
    beepIntervalMax = 1.0
    directionLeftThreshold = 0.33
    directionRightThreshold = 0.66
    speechRepeatInterval = 4.0
    speechChangeInterval = 2.0
    allowPartialNavigation = true
    announceRejected = true

    // Distance Feedback Settings
    distanceMin = 0.2
    distanceMax = 3.0
    volumeMin = 0.2
    volumeMax = 1.0
    volumeCurve = .linear

    // Camera Settings
    useARMode = false

    // Detection Settings
    confidenceThreshold = 0.4
    verificationCooldown = 2.0
    targetLifetime = 700
    maxLostFrames = 4

    // Feedback Mode Settings
    enableBeeps = true
    enableHaptics = false
    enableSpeech = true
    speechRate = 0.5

    // Advanced Settings
    smoothingAlpha = 0.2
    developerMode = false
    debugOverlayEnabled = false
    

    // Force UserDefaults to synchronize changes
    UserDefaults.standard.synchronize()

    // Notify observers that all properties have changed
    self.objectWillChange.send()

    print("Settings reset to defaults")
  }
}
