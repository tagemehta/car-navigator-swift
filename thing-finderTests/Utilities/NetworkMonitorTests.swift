//  NetworkMonitorTests.swift
//  thing-finderTests
//
//  Regression tests for `NetworkMonitor.currentConnectivity()`, which awaits
//  the real (not optimistic) connectivity state so callers like
//  `InputView.attemptStartSearch()` don't trust a cold-start guess.

import XCTest

@testable import thing_finder

final class NetworkMonitorTests: XCTestCase {

  /// `currentConnectivity()` must resolve (not hang) and agree with
  /// `isConnected` once resolved — whether it resolves via the real
  /// `NWPathMonitor` callback or the timeout fallback.
  func test_currentConnectivity_resolvesAndMatchesIsConnected() async {
    let monitor = NetworkMonitor.shared

    let result = await monitor.currentConnectivity()

    XCTAssertEqual(result, monitor.isConnected)
  }

  /// Multiple overlapping callers (e.g. rapid taps on "Start Searching")
  /// must each get a resumed result without crashing from a double-resume
  /// of a shared continuation.
  func test_currentConnectivity_handlesConcurrentCallers() async {
    let monitor = NetworkMonitor.shared

    async let first = monitor.currentConnectivity()
    async let second = monitor.currentConnectivity()
    async let third = monitor.currentConnectivity()

    let results = await [first, second, third]

    XCTAssertEqual(results.count, 3)
    XCTAssertTrue(results.allSatisfy { $0 == monitor.isConnected })
  }
}
