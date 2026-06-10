//  DistanceMilestoneControllerTests.swift
//  thing-finderTests
//
//  Unit tests for DistanceMilestoneController.
//  Covers: milestone crossing, ordering, hysteresis re-arm, one-per-tick,
//  speech-disabled, nil distance, reset.

import XCTest

@testable import thing_finder

final class DistanceMilestoneControllerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var cache: AnnouncementCache!
  private var settings: Settings!
  private var config: NavigationFeedbackConfig!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
    config = NavigationFeedbackConfig(
      speechRepeatInterval: 6.0,
      directionChangeInterval: 4.0,
      waitingPhraseCooldown: 10.0,
      retryPhraseCooldown: 8.0
    )
    config.milestoneCooldown = 0.0  // Suppress inter-milestone cooldown for simpler tests
  }

  override func tearDown() {
    mockSpeaker = nil
    cache = nil
    settings = nil
    config = nil
    super.tearDown()
  }

  private func makeController() -> DistanceMilestoneController {
    DistanceMilestoneController(
      speaker: mockSpeaker, cache: cache, settings: settings, config: config)
  }

  // MARK: - Nil distance (non-LiDAR)

  func test_nilDistance_noSpeech() {
    let controller = makeController()

    controller.tick(distance: nil, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Speech disabled

  func test_speechDisabled_noSpeech() {
    settings.enableSpeech = false
    let controller = makeController()

    controller.tick(distance: 5.0, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Single milestone crossing

  func test_crossingTenMeter_speaks() {
    let controller = makeController()

    controller.tick(distance: 10.0, timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("10"))
  }

  func test_crossingFiveMeter_speaks() {
    // Approach from outside 10m so 10m fires first, then 5m.
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m fires
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m fires

    XCTAssertTrue(mockSpeaker.didSpeakContaining("5"))
  }

  func test_crossingTwoMeter_speaks() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.8, timestamp: now)  // 2 m

    XCTAssertTrue(mockSpeaker.didSpeakContaining("2"))
  }

  func test_crossingOneMeter_speaksAlmostThere() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.8, timestamp: now)  // 2 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.8, timestamp: now)  // 1 m

    XCTAssertTrue(mockSpeaker.didSpeakContaining("almost there"))
  }

  // MARK: - No repeat for same threshold

  func test_sameThreshold_firesOnlyOnce() {
    let controller = makeController()
    var now = Date()

    // Pre-cross 10 m so we isolate the 5 m behaviour.
    controller.tick(distance: 9.0, timestamp: now)  // 10 m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)

    // Same distance again — must not repeat
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2, "Same threshold must not repeat")
  }

  // MARK: - Milestones fire in order (farthest first)

  func test_approachingFromFar_milestonesFireInOrder() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 11.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "No milestone above 10m")

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 9.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("10"))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("5"))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.5, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 3)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("2"))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.8, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 4)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("almost there"))
  }

  // MARK: - At most one milestone per tick

  func test_jumpingInsideMultipleThresholds_firesOneFarthestFirst() {
    // User "teleports" from 12m to 3m — inside both 10m and 5m thresholds.
    // Only the farthest uncrossed (10m) should fire this tick.
    let controller = makeController()
    let now = Date()

    controller.tick(distance: 3.0, timestamp: now)

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("10"))
  }

  func test_jumpingInsideMultipleThresholds_firesRemaining_onNextTicks() {
    let controller = makeController()
    var now = Date()

    // Tick 1: 10m fires
    controller.tick(distance: 3.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Tick 2: 5m fires (10m already crossed)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 3.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("5"))

    // Tick 3: 2m fires (3 <= 2 is false → actually 3 > 2 so 2m should NOT fire)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 3.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2, "3m is not within 2m threshold")
  }

  // MARK: - Hysteresis re-arm

  func test_backingAway_rearmsThreshold() {
    let controller = makeController()
    var now = Date()

    // Approach to fire both 10m and 5m milestones.
    controller.tick(distance: 9.0, timestamp: now)  // 10m fires
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)  // 5m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)

    // Back away well past 5m + 1.5m hysteresis = 6.5m — 5m re-arms.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 7.0, timestamp: now)
    let countAfterBackingAway = mockSpeaker.speakCallCount  // still 2

    // Approach again — 5m fires again.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertGreaterThan(
      mockSpeaker.speakCallCount, countAfterBackingAway,
      "5m milestone should re-fire after re-arm")
    XCTAssertTrue(mockSpeaker.didSpeakContaining("5"))
  }

  func test_slightlyBackingAway_doesNotRearm() {
    let controller = makeController()
    var now = Date()

    // Approach to fire both 10m and 5m milestones.
    controller.tick(distance: 9.0, timestamp: now)  // 10m fires
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)  // 5m fires
    let countAfterCross = mockSpeaker.speakCallCount  // 2

    // Back away to 6m — less than 5m + 1.5m = 6.5m, not enough to re-arm 5m.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 6.0, timestamp: now)

    // Come back to 4m — 5m should NOT fire again.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertEqual(
      mockSpeaker.speakCallCount, countAfterCross,
      "5m should not re-fire when re-arm threshold not cleared")
  }

  // MARK: - Reset

  func test_reset_rearmsAllMilestones() {
    let controller = makeController()
    var now = Date()

    // Cross all milestones
    controller.tick(distance: 9.0, timestamp: now)  // 10m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)  // 5m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.5, timestamp: now)  // 2m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.5, timestamp: now)  // 1m

    let countBefore = mockSpeaker.speakCallCount
    XCTAssertEqual(countBefore, 4)

    // Reset and approach again
    controller.reset()
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 9.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 5, "10m should fire again after reset")
  }

  // MARK: - Milestone cooldown

  func test_milestoneCooldown_suppressesIfOtherSpeechJustFired() {
    config.milestoneCooldown = 2.0
    let controller = makeController()
    let now = Date()

    // Simulate another controller just spoke
    cache.lastGlobal = (phrase: "Found it", time: now)

    // Try to cross 10m — should be suppressed by cooldown
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(0.5))

    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "Milestone suppressed by recent speech")
  }

  func test_milestoneCooldown_firesAfterWindowExpires() {
    config.milestoneCooldown = 2.0
    let controller = makeController()
    let now = Date()

    cache.lastGlobal = (phrase: "Found it", time: now)

    // After cooldown expires, milestone fires
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(2.5))

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("10"))
  }
}
