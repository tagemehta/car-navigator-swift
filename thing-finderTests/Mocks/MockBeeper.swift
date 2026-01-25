//  MockBeeper.swift
//  thing-finderTests
//
//  Mock implementation of Beeper for testing HapticBeepController.

import Foundation

@testable import thing_finder

final class MockBeeper: Beeper {
  /// Whether the beeper is currently active.
  private(set) var isPlaying = false

  /// Number of times start() was called.
  private(set) var startCallCount = 0

  /// Number of times stop() was called.
  private(set) var stopCallCount = 0

  /// Last frequency passed to start().
  private(set) var lastFrequency: Double?

  /// Last volume passed to start().
  private(set) var lastVolume: Float?

  func start(frequency: Double, volume: Float) {
    isPlaying = true
    startCallCount += 1
    lastFrequency = frequency
    lastVolume = volume
  }

  func stop() {
    isPlaying = false
    stopCallCount += 1
  }

  /// Reset all recorded state.
  func reset() {
    isPlaying = false
    startCallCount = 0
    stopCallCount = 0
    lastFrequency = nil
    lastVolume = nil
  }
}

/// Mock implementation of SmoothBeeper for testing interval-based beeping.
final class MockSmoothBeeper: SmoothBeeperProtocol {
  private(set) var isPlaying = false
  private(set) var startCallCount = 0
  private(set) var stopCallCount = 0
  private(set) var lastInterval: TimeInterval?
  private(set) var updateIntervalCallCount = 0

  func start(frequency: Double, volume: Float) {
    isPlaying = true
    startCallCount += 1
  }

  func stop() {
    isPlaying = false
    stopCallCount += 1
  }

  func start(interval: TimeInterval) {
    isPlaying = true
    startCallCount += 1
    lastInterval = interval
  }

  func updateInterval(to interval: TimeInterval, smoothly: Bool) {
    lastInterval = interval
    updateIntervalCallCount += 1
  }

  func reset() {
    isPlaying = false
    startCallCount = 0
    stopCallCount = 0
    lastInterval = nil
    updateIntervalCallCount = 0
  }
}
