//  HapticBeepControllerTests.swift
//  thing-finderTests
//
//  Unit tests for HapticBeepController beep feedback logic.

import CoreGraphics
import XCTest

@testable import thing_finder

final class HapticBeepControllerTests: XCTestCase {

  private var mockBeeper: MockSmoothBeeper!
  private var settings: Settings!

  override func setUp() {
    super.setUp()
    mockBeeper = MockSmoothBeeper()
    settings = TestSettings.makeDefault()
  }

  override func tearDown() {
    mockBeeper = nil
    settings = nil
    super.tearDown()
  }

  private func makeController() -> HapticBeepController {
    return HapticBeepController(beeper: mockBeeper, settings: settings)
  }

  // MARK: - Beep Enable/Disable

  func test_tick_noBeepWhenDisabled() {
    settings.enableBeeps = false
    let controller = makeController()

    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())

    XCTAssertEqual(mockBeeper.startCallCount, 0)
  }

  func test_tick_startsBeepWhenEnabled() {
    settings.enableBeeps = true
    let controller = makeController()

    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())

    XCTAssertEqual(mockBeeper.startCallCount, 1)
    XCTAssertTrue(mockBeeper.isPlaying)
  }

  // MARK: - Target Presence

  func test_tick_startsBeepWhenTargetPresent() {
    let controller = makeController()

    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())

    XCTAssertTrue(mockBeeper.isPlaying)
  }

  func test_tick_stopsBeepWhenTargetLost() {
    let controller = makeController()

    // Start with target
    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())
    XCTAssertTrue(mockBeeper.isPlaying)

    // Target lost
    controller.tick(targetBox: nil, timestamp: Date())
    XCTAssertFalse(mockBeeper.isPlaying)
    XCTAssertEqual(mockBeeper.stopCallCount, 1)
  }

  func test_tick_stopsBeepWhenBeepsDisabled() {
    let controller = makeController()

    // Start with target and beeps enabled
    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())
    XCTAssertTrue(mockBeeper.isPlaying)

    // Disable beeps
    settings.enableBeeps = false
    controller.tick(targetBox: targetBox, timestamp: Date())
    XCTAssertFalse(mockBeeper.isPlaying)
  }

  // MARK: - Centering Score

  func test_tick_adjustsIntervalByCentering_centered() {
    let controller = makeController()

    // Perfectly centered target (midX = 0.5)
    let centeredBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: centeredBox, timestamp: Date())

    XCTAssertNotNil(mockBeeper.lastInterval)
    let centeredInterval = mockBeeper.lastInterval!

    // Off-center target (midX = 0.1)
    mockBeeper.reset()
    let offCenterBox = CGRect(x: 0.0, y: 0.25, width: 0.2, height: 0.5)
    controller.tick(targetBox: offCenterBox, timestamp: Date())

    XCTAssertNotNil(mockBeeper.lastInterval)
    let offCenterInterval = mockBeeper.lastInterval!

    // Centered should have shorter interval (faster beeps)
    XCTAssertLessThan(centeredInterval, offCenterInterval)
  }

  func test_tick_updatesIntervalSmoothly() {
    let controller = makeController()

    // Start with centered target
    let centeredBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: centeredBox, timestamp: Date())
    XCTAssertEqual(mockBeeper.startCallCount, 1)

    // Move target off-center - should update interval, not restart
    let offCenterBox = CGRect(x: 0.0, y: 0.25, width: 0.2, height: 0.5)
    controller.tick(targetBox: offCenterBox, timestamp: Date())

    XCTAssertEqual(mockBeeper.startCallCount, 1)  // Still only 1 start
    XCTAssertGreaterThan(mockBeeper.updateIntervalCallCount, 0)
  }

  // MARK: - Edge Cases

  func test_tick_handlesNilTargetInitially() {
    let controller = makeController()

    controller.tick(targetBox: nil, timestamp: Date())

    XCTAssertFalse(mockBeeper.isPlaying)
    XCTAssertEqual(mockBeeper.startCallCount, 0)
    XCTAssertEqual(mockBeeper.stopCallCount, 0)  // Nothing to stop
  }

  func test_tick_doesNotStopTwice() {
    let controller = makeController()

    // Start then stop
    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    controller.tick(targetBox: targetBox, timestamp: Date())
    controller.tick(targetBox: nil, timestamp: Date())
    XCTAssertEqual(mockBeeper.stopCallCount, 1)

    // Another nil tick should not call stop again
    controller.tick(targetBox: nil, timestamp: Date())
    XCTAssertEqual(mockBeeper.stopCallCount, 1)
  }

  func test_tick_restartsAfterStop() {
    let controller = makeController()

    let targetBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    // Start
    controller.tick(targetBox: targetBox, timestamp: Date())
    XCTAssertEqual(mockBeeper.startCallCount, 1)

    // Stop
    controller.tick(targetBox: nil, timestamp: Date())
    XCTAssertFalse(mockBeeper.isPlaying)

    // Restart
    controller.tick(targetBox: targetBox, timestamp: Date())
    XCTAssertEqual(mockBeeper.startCallCount, 2)
    XCTAssertTrue(mockBeeper.isPlaying)
  }
}
