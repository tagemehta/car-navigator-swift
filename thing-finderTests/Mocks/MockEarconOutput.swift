//  MockEarconOutput.swift
//  thing-finderTests
//
//  Test double for EarconOutput used in PreMatchFeedbackControllerTests.

import Foundation

@testable import thing_finder

final class MockEarconOutput: EarconOutput {
  private(set) var playCallCount = 0

  func play() {
    playCallCount += 1
  }

  func reset() {
    playCallCount = 0
  }
}
