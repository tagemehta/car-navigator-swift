//  MockCompassProvider.swift
//  thing-finderTests
//
//  Mock implementation of CompassProvider for unit tests.
//  Allows tests to control compass heading values deterministically.

import Foundation

@testable import thing_finder

final class MockCompassProvider: CompassProvider {
  var degrees: Double

  init(degrees: Double = 0.0) {
    self.degrees = degrees
  }
}
