//  APIHealthMonitorTests.swift
//  thing-finderTests
//
//  Unit tests for APIHealthMonitor.

import XCTest

@testable import thing_finder

final class APIHealthMonitorTests: XCTestCase {

  func test_notDegraded_belowThreshold() {
    let monitor = APIHealthMonitor(failureThreshold: 3)

    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)

    XCTAssertFalse(monitor.isDegraded)
  }

  func test_degraded_atThreshold() {
    let monitor = APIHealthMonitor(failureThreshold: 3)

    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)

    XCTAssertTrue(monitor.isDegraded)
  }

  func test_nonConnectivityFailures_doNotCount() {
    let monitor = APIHealthMonitor(failureThreshold: 3)

    monitor.recordFailure(isConnectivityRelated: false)
    monitor.recordFailure(isConnectivityRelated: false)
    monitor.recordFailure(isConnectivityRelated: false)

    XCTAssertFalse(monitor.isDegraded)
  }

  func test_success_resetsCounterAndClearsDegraded() {
    let monitor = APIHealthMonitor(failureThreshold: 3)

    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)
    XCTAssertTrue(monitor.isDegraded)

    monitor.recordSuccess()
    XCTAssertFalse(monitor.isDegraded)

    // Counter reset — a single subsequent failure shouldn't re-flag.
    monitor.recordFailure(isConnectivityRelated: true)
    XCTAssertFalse(monitor.isDegraded)
  }

  func test_intermittentSuccess_preventsFlagging() {
    let monitor = APIHealthMonitor(failureThreshold: 3)

    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordFailure(isConnectivityRelated: true)
    monitor.recordSuccess()
    monitor.recordFailure(isConnectivityRelated: true)

    XCTAssertFalse(monitor.isDegraded)
  }
}
