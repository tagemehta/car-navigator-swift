import CoreGraphics
import Foundation

/// Two-channel feedback controller:
/// - **Beeps**: driven by centering (direction) — faster when target is centered.
/// - **Haptics**: driven by distance — faster when closer. Falls back to a
///   steady pulse when distance is unavailable (non-LiDAR devices).
final class HapticBeepController {
  private let beeper: SmoothBeeperProtocol
  private let hapticManager: HapticManagerProtocol
  private let settings: Settings
  private var isBeeping = false
  private var isHapticPulsing = false

  init(
    beeper: SmoothBeeperProtocol,
    hapticManager: HapticManagerProtocol? = nil,
    settings: Settings
  ) {
    self.beeper = beeper
    self.hapticManager = hapticManager ?? HapticManager(settings: settings)
    self.settings = settings
  }

  /// Call every frame.
  /// - Parameters:
  ///   - targetBox: optional bounding box of the target in normalized coordinates.
  ///   - distance: optional distance to target in meters (from LiDAR/AR).
  func tick(targetBox: CGRect?, distance: Double? = nil, timestamp: Date) {
    tickBeeps(targetBox: targetBox)
    tickHaptics(targetBox: targetBox, distance: distance)
  }

  // MARK: - Beep Feedback (centering only)

  private func tickBeeps(targetBox: CGRect?) {
    guard settings.enableBeeps else {
      stopBeepsIfNeeded()
      return
    }
    guard let box = targetBox else {
      stopBeepsIfNeeded()
      return
    }

    let centeringScore = abs(box.midX - 0.5)
    let interval = settings.calculateBeepInterval(distanceFromCenter: centeringScore)

    if !isBeeping {
      beeper.start(interval: interval)
      isBeeping = true
    } else {
      beeper.updateInterval(to: interval, smoothly: true)
    }
  }

  private func stopBeepsIfNeeded() {
    if isBeeping {
      beeper.stop()
      isBeeping = false
    }
  }

  // MARK: - Haptic Feedback (distance only, steady fallback)

  /// Default steady pulse when distance is unavailable (e.g. non-LiDAR device).
  private static let steadyPulseInterval: TimeInterval = 6.0

  private func tickHaptics(targetBox: CGRect?, distance: Double?) {
    guard settings.enableHaptics else {
      stopHapticsIfNeeded()
      return
    }
    guard targetBox != nil else {
      stopHapticsIfNeeded()
      return
    }

    let interval: TimeInterval
    if let distance {
      interval = settings.calculateBeepInterval(distanceMeters: distance)
    } else {
      interval = Self.steadyPulseInterval
    }

    if !isHapticPulsing {
      hapticManager.startPulsing(interval: interval)
      isHapticPulsing = true
    } else {
      hapticManager.updateInterval(to: interval, smoothly: true)
    }
  }

  private func stopHapticsIfNeeded() {
    if isHapticPulsing {
      hapticManager.stopPulsing()
      isHapticPulsing = false
    }
  }

}
