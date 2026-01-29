import Foundation
import UIKit

/// Protocol for haptic feedback management.
/// Mirrors the audio beeper pattern for consistency.
public protocol HapticManagerProtocol {
  /// Start pulsing haptics at the given interval.
  func startPulsing(interval: TimeInterval)
  
  /// Update the pulse interval (for centering feedback).
  func updateInterval(to newInterval: TimeInterval, smoothly: Bool)
  
  /// Stop any ongoing haptic pulses.
  func stopPulsing()
  
  /// Play a success haptic (car matched).
  func playSuccess()
  
  /// Play a failure haptic (car rejected).
  func playFailure()
}

/// Concrete haptic manager using UIKit feedback generators.
/// Design goals (matches project principles):
/// • Safe from bugs   – one timer, proper generator lifecycle.
/// • Easy to understand – mirrors SmoothBeeper's interval-based API.
/// • Ready for change   – protocol-based for testability.
final class HapticManager: HapticManagerProtocol {
  private let settings: Settings
  
  private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
  private let notificationGenerator = UINotificationFeedbackGenerator()
  
  private var timer: Timer?
  private var lastPulseTime: Date = .distantPast
  private var currentInterval: TimeInterval = 0.5
  private var targetInterval: TimeInterval = 0.5
  
  private let alpha: Double = 0.2
  private let minInterval: TimeInterval = 0.1
  
  init(settings: Settings = Settings()) {
    self.settings = settings
    impactGenerator.prepare()
    notificationGenerator.prepare()
  }
  
  deinit {
    stopPulsing()
  }
  
  // MARK: - Pulsing API
  
  func startPulsing(interval: TimeInterval) {
    stopPulsing()
    targetInterval = max(minInterval, interval)
    currentInterval = targetInterval
    lastPulseTime = Date()
    pulse()
    scheduleNextPulse(after: currentInterval)
  }
  
  func updateInterval(to newInterval: TimeInterval, smoothly: Bool) {
    let safe = max(minInterval, newInterval)
    targetInterval = safe
    if !smoothly {
      currentInterval = safe
      rescheduleTimer()
      return
    }
    currentInterval = (1 - alpha) * currentInterval + alpha * targetInterval
    rescheduleTimer()
  }
  
  func stopPulsing() {
    timer?.invalidate()
    timer = nil
  }
  
  // MARK: - One-shot Haptics
  
  func playSuccess() {
    notificationGenerator.notificationOccurred(.success)
  }
  
  func playFailure() {
    notificationGenerator.notificationOccurred(.error)
  }
  
  // MARK: - Private
  
  private func rescheduleTimer() {
    guard timer != nil else { return }
    let elapsed = Date().timeIntervalSince(lastPulseTime)
    let remaining = max(0.0, currentInterval - elapsed)
    scheduleNextPulse(after: remaining)
  }
  
  private func scheduleNextPulse(after delay: TimeInterval) {
    timer?.invalidate()
    let newTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      self?.handleTimerFire()
    }
    RunLoop.main.add(newTimer, forMode: .common)
    timer = newTimer
  }
  
  private func handleTimerFire() {
    pulse()
    scheduleNextPulse(after: currentInterval)
  }
  
  private func pulse() {
    impactGenerator.impactOccurred()
    lastPulseTime = Date()
  }
}
