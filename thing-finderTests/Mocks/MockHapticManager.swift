//  MockHapticManager.swift
//  thing-finderTests
//
//  Mock implementation of HapticManagerProtocol for testing.

import Foundation

@testable import thing_finder

final class MockHapticManager: HapticManagerProtocol {
  private(set) var isPulsing = false
  private(set) var startPulsingCallCount = 0
  private(set) var stopPulsingCallCount = 0
  private(set) var updateIntervalCallCount = 0
  private(set) var successCallCount = 0
  private(set) var failureCallCount = 0
  private(set) var lastInterval: TimeInterval?

  func startPulsing(interval: TimeInterval) {
    isPulsing = true
    startPulsingCallCount += 1
    lastInterval = interval
  }

  func updateInterval(to newInterval: TimeInterval, smoothly: Bool) {
    lastInterval = newInterval
    updateIntervalCallCount += 1
  }

  func stopPulsing() {
    isPulsing = false
    stopPulsingCallCount += 1
  }

  func playSuccess() {
    successCallCount += 1
  }

  func playFailure() {
    failureCallCount += 1
  }

  func reset() {
    isPulsing = false
    startPulsingCallCount = 0
    stopPulsingCallCount = 0
    updateIntervalCallCount = 0
    successCallCount = 0
    failureCallCount = 0
    lastInterval = nil
  }
}
