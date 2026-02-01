import CoreGraphics
import Foundation

/// Converts car centering → tone frequency & volume and drives a concrete `Beeper`.
/// Also drives haptic pulses for deafblind users when haptics are enabled.
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
  /// - Parameter targetBox: optional bounding box of the target in normalized coordinates.
  func tick(targetBox: CGRect?, timestamp: Date) {
    tickBeeps(targetBox: targetBox)
    tickHaptics(targetBox: targetBox)
  }

  // MARK: - Beep Feedback

  private func tickBeeps(targetBox: CGRect?) {
    guard settings.enableBeeps else {
      stopBeepsIfNeeded()
      return
    }
    guard let box = targetBox else {
      stopBeepsIfNeeded()
      return
    }

    let interval = calculateInterval(for: box)

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

  // MARK: - Haptic Feedback

  private func tickHaptics(targetBox: CGRect?) {
    guard settings.enableHaptics else {
      stopHapticsIfNeeded()
      return
    }
    guard let box = targetBox else {
      stopHapticsIfNeeded()
      return
    }

    let interval = calculateInterval(for: box)

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

  // MARK: - Shared

  private func calculateInterval(for box: CGRect) -> TimeInterval {
    let centerX = box.midX
    let centeringScore = abs(centerX - 0.5)
    return settings.calculateBeepInterval(distanceFromCenter: centeringScore)
  }
}
