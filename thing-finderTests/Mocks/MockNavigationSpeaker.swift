//  MockNavigationSpeaker.swift
//  thing-finderTests
//
//  Mock implementation of NavigationSpeaker for unit tests.
//  Records tick calls and the parameters passed to them.

import CoreGraphics
import Foundation

@testable import thing_finder

final class MockNavigationSpeaker: NavigationSpeaker {
  /// Records each call to tick() for verification
  private(set) var tickCallCount = 0
  /// The most recent `distance` argument passed to tick().
  private(set) var lastDistance: Double?
  /// The most recent `targetBox` argument passed to tick().
  private(set) var lastTargetBox: CGRect?

  func tick(
    at timestamp: Date,
    candidates: [Candidate],
    targetBox: CGRect?,
    distance: Double?
  ) {
    tickCallCount += 1
    lastTargetBox = targetBox
    lastDistance = distance
  }

  func reset() {
    tickCallCount = 0
    lastDistance = nil
    lastTargetBox = nil
  }
}
