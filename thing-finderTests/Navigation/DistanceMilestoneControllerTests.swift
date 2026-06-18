//  DistanceMilestoneControllerTests.swift
//  thing-finderTests
//
//  Unit tests for DistanceMilestoneController.
//
//  Covers: milestone crossing, closest-first semantics, ordering, hysteresis
//  re-arm, one-per-tick, speech-disabled, nil distance, reset, cooldown.
//
//  String assertions use `expectedLabel(meters:)` — a formatter configured
//  identically to the production controller — so tests are locale-independent
//  (feet on en_US, metres on en_GB, etc.).

import XCTest

@testable import thing_finder

final class DistanceMilestoneControllerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var cache: AnnouncementCache!
  private var settings: Settings!
  private var config: NavigationFeedbackConfig!

  /// Formatter that mirrors the one inside DistanceMilestoneController so
  /// test assertions always match what the controller actually speaks,
  /// regardless of the system locale.
  private let formatter: MeasurementFormatter = {
    let f = MeasurementFormatter()
    f.unitOptions = .naturalScale
    f.unitStyle = .long
    f.numberFormatter.maximumFractionDigits = 0
    return f
  }()

  private func expectedLabel(meters: Double) -> String {
    formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
  }

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
    config = NavigationFeedbackConfig(
      speechRepeatInterval: 6.0,
      directionChangeInterval: 4.0,
      retryPhraseCooldown: 8.0
    )
    config.milestoneCooldown = 0.0  // Suppress inter-announcement cooldown for simpler tests
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

    controller.tick(distance: 9.0, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 10)),
      "Expected '\(expectedLabel(meters: 10))' but heard: \(mockSpeaker.spokenPhrases)")
  }

  func test_crossingFiveMeter_speaks() {
    // Approach from outside 10 m so 10 m fires first, then 5 m.
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m fires
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m fires

    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 5)),
      "Expected '\(expectedLabel(meters: 5))' but heard: \(mockSpeaker.spokenPhrases)")
  }

  func test_crossingTwoMeter_speaks() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.8, timestamp: now)

    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 2)),
      "Expected '\(expectedLabel(meters: 2))' but heard: \(mockSpeaker.spokenPhrases)")
  }

  func test_crossingOneMeter_speaksAlmostThere() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.8, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.8, timestamp: now)

    XCTAssertTrue(mockSpeaker.didSpeakContaining("almost there"))
  }

  // MARK: - No repeat for same threshold

  func test_sameThreshold_firesOnlyOnce() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)  // 5 m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)

    // Same distance again — must not repeat.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.5, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2, "Same threshold must not repeat")
  }

  // MARK: - Closest-first: skipped thresholds are silently marked

  func test_jumpingInsideMultipleThresholds_announcesClosest() {
    // User "jumps" from 12 m to 3 m — inside both 10 m and 5 m thresholds.
    // Should announce the CLOSEST (5 m) and silently mark 10 m as done.
    let controller = makeController()

    controller.tick(distance: 3.0, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 1, "Only one announcement per tick")
    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 5)),
      "Should announce the closest threshold (5 m '\(expectedLabel(meters: 5))'), "
        + "not the farthest (10 m '\(expectedLabel(meters: 10))'). "
        + "Heard: \(mockSpeaker.spokenPhrases)")
    XCTAssertFalse(
      mockSpeaker.didSpeak(expectedLabel(meters: 10)),
      "10 m should be silently marked, not announced")
  }

  func test_jumpingInsideMultipleThresholds_fartherThresholdSilentlyMarked() {
    // After jumping to 3 m, both 5 m and 10 m are crossed.
    // A subsequent tick at 3 m should not fire again for either.
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 3.0, timestamp: now)  // 5 m announced; 10 m silently marked
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 3.0, timestamp: now)  // nothing new — both already crossed
    XCTAssertEqual(
      mockSpeaker.speakCallCount, 1,
      "No re-announcement for already-crossed thresholds")
  }

  func test_jumpingToOneMeter_announcesAlmostThere() {
    // Jump from outside straight to 0.5 m — all thresholds crossed; announces "almost there".
    let controller = makeController()

    controller.tick(distance: 0.5, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("almost there"))
  }

  // MARK: - Natural approach fires in order

  func test_approachingFromFar_milestonesFireInOrder() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 11.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "No milestone above 10 m")

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 9.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeak(expectedLabel(meters: 10)))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
    XCTAssertTrue(mockSpeaker.didSpeak(expectedLabel(meters: 5)))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.5, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 3)
    XCTAssertTrue(mockSpeaker.didSpeak(expectedLabel(meters: 2)))

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.8, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 4)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("almost there"))
  }

  // MARK: - Hysteresis re-arm

  func test_backingAway_rearmsThreshold() {
    let controller = makeController()
    var now = Date()

    // Approach to fire both 10 m and 5 m milestones.
    controller.tick(distance: 9.0, timestamp: now)  // 10 m fires
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)  // 5 m fires
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)

    // Back away well past 5 m + 1.5 m hysteresis = 6.5 m → 5 m re-arms.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 7.0, timestamp: now)
    let countAfterBackingAway = mockSpeaker.speakCallCount  // still 2

    // Approach again — 5 m fires once more.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertGreaterThan(
      mockSpeaker.speakCallCount, countAfterBackingAway,
      "5 m milestone should re-fire after re-arm")
    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 5)),
      "Expected '\(expectedLabel(meters: 5))' but heard: \(mockSpeaker.spokenPhrases)")
  }

  func test_slightlyBackingAway_doesNotRearm() {
    let controller = makeController()
    var now = Date()

    controller.tick(distance: 9.0, timestamp: now)  // 10 m
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)  // 5 m
    let countAfterCross = mockSpeaker.speakCallCount  // 2

    // Back away to 6 m — less than 5 m + 1.5 m = 6.5 m → 5 m does NOT re-arm.
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 6.0, timestamp: now)

    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    XCTAssertEqual(
      mockSpeaker.speakCallCount, countAfterCross,
      "5 m should not re-fire when re-arm threshold was not cleared")
  }

  // MARK: - Reset

  func test_reset_rearmsAllMilestones() {
    let controller = makeController()
    var now = Date()

    // Cross all four milestones.
    controller.tick(distance: 9.0, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 4.0, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 1.5, timestamp: now)
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 0.5, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 4)

    // Reset and approach again — milestones should fire fresh.
    controller.reset()
    now = now.addingTimeInterval(1.0)
    controller.tick(distance: 9.0, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 5, "10 m should fire again after reset")
  }

  // MARK: - Milestone cooldown (don't interrupt other controllers)

  func test_milestoneCooldown_suppressesIfOtherSpeechJustFired() {
    config.milestoneCooldown = 2.0
    let controller = makeController()
    let now = Date()

    cache.lastGlobal = (phrase: "Found it", time: now)

    // Within 2 s cooldown — suppressed; thresholds not yet marked.
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(0.5))

    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "Milestone suppressed by recent speech")
  }

  func test_milestoneCooldown_firesAfterWindowExpires() {
    config.milestoneCooldown = 2.0
    let controller = makeController()
    let now = Date()

    cache.lastGlobal = (phrase: "Found it", time: now)

    // After 2 s window expires — should fire.
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(2.5))

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(
      mockSpeaker.didSpeak(expectedLabel(meters: 10)),
      "Expected '\(expectedLabel(meters: 10))' but heard: \(mockSpeaker.spokenPhrases)")
  }

  func test_milestoneCooldown_thresholdsNotMarkedWhenSuppressed() {
    // If cooldown suppresses a tick, the thresholds remain available so they fire
    // on the very next eligible tick rather than being silently swallowed.
    config.milestoneCooldown = 2.0
    let controller = makeController()
    let now = Date()

    cache.lastGlobal = (phrase: "Found it", time: now)

    // Suppressed tick — milestone NOT marked.
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(0.5))
    XCTAssertEqual(mockSpeaker.speakCallCount, 0)

    // After cooldown expires milestone fires.
    controller.tick(distance: 9.0, timestamp: now.addingTimeInterval(2.5))
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
  }
}
