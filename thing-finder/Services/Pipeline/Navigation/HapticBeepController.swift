import CoreGraphics
import Foundation

/// Converts car centering → tone frequency & volume and drives a concrete `Beeper`.
final class HapticBeepController {
  private let beeper: Beeper
  private let settings: Settings
  private var isBeeping = false

  init(beeper: Beeper, settings: Settings) {
    self.beeper = beeper
    self.settings = settings
  }

  /// Call every frame.
  /// - Parameter targetBox: optional bounding box of the target in normalized coordinates.
  func tick(targetBox: CGRect?, timestamp: Date) {
    guard settings.enableBeeps else {
      stopIfNeeded()
      return
    }
    guard let box = targetBox else {
      stopIfNeeded()
      return
    }

    // Calculate centering score: 0 = perfectly centered, 1 = at edge
    let centerX = box.midX
    let centeringScore = abs(centerX - 0.5)  // 0 to 1 scale

    // Map centering score to beep interval (seconds). More centered → shorter interval
    let interval = settings.calculateBeepInterval(distanceFromCenter: centeringScore)

    if !isBeeping {
      // Start directly with interval-based API for a smoother first beep
      (beeper as? SmoothBeeper)?.start(interval: interval)
      isBeeping = true
    } else {
      // Smoothly adjust toward the new interval
      (beeper as? SmoothBeeper)?.updateInterval(to: interval, smoothly: true)
    }
  }

  private func stopIfNeeded() {
    if isBeeping {
      beeper.stop()
      isBeeping = false
    }
  }
}
