//  DirectionSpeechControllerTests.swift
//  thing-finderTests
//
//  Unit tests for DirectionSpeechController.
//  Covers: change-gated only, debounce, first-entry, reset, speech-disabled.

import CoreGraphics
import XCTest

@testable import thing_finder

final class DirectionSpeechControllerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var cache: AnnouncementCache!
  private var settings: Settings!
  private var config: NavigationFeedbackConfig!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
    // Short debounce so tests don't need to advance time by 4 seconds.
    config = NavigationFeedbackConfig(
      speechRepeatInterval: 6.0,
      directionChangeInterval: 0.5,
      waitingPhraseCooldown: 10.0,
      retryPhraseCooldown: 8.0
    )
  }

  override func tearDown() {
    mockSpeaker = nil
    cache = nil
    settings = nil
    config = nil
    super.tearDown()
  }

  private func makeController() -> DirectionSpeechController {
    DirectionSpeechController(
      cache: cache, config: config, speaker: mockSpeaker, settings: settings)
  }

  // MARK: - First entry always fires

  func test_firstTick_alwaysSpeaksDirection() {
    let controller = makeController()
    // Center box (midX = 0.5 → "straight ahead")
    let box = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)

    controller.tick(targetBox: box, distance: nil, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("straight ahead"))
  }

  // MARK: - No speech for nil targetBox

  func test_nilTargetBox_noSpeech() {
    let controller = makeController()

    controller.tick(targetBox: nil, distance: nil, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - No repeat for same category

  func test_sameDirection_doesNotRepeat() {
    let controller = makeController()
    let box = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)  // center
    let now = Date()

    controller.tick(targetBox: box, distance: nil, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Second tick with same category — well past debounce window
    controller.tick(targetBox: box, distance: nil, timestamp: now.addingTimeInterval(10.0))
    XCTAssertEqual(mockSpeaker.speakCallCount, 1, "Same direction must not repeat")
  }

  // MARK: - Fires on direction change

  func test_directionChange_centerToLeft_speaks() {
    let controller = makeController()
    let now = Date()

    // Center box first
    let centerBox = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: centerBox, distance: nil, timestamp: now)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("straight ahead"))

    // Move to left — past debounce window
    let leftBox = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: leftBox, distance: nil, timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("on your left"))
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
  }

  func test_directionChange_leftToRight_speaks() {
    let controller = makeController()
    let now = Date()

    let leftBox = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: leftBox, distance: nil, timestamp: now)

    let rightBox = CGRect(x: 0.8, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: rightBox, distance: nil, timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("on your right"))
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
  }

  // MARK: - Debounce prevents rapid oscillation

  func test_directionChange_withinDebounce_suppressed() {
    let controller = makeController()
    let now = Date()

    let centerBox = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: centerBox, distance: nil, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Immediately (within 0.5s debounce) change direction
    let leftBox = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: leftBox, distance: nil, timestamp: now.addingTimeInterval(0.1))

    // Should be suppressed — debounce hasn't elapsed
    XCTAssertEqual(mockSpeaker.speakCallCount, 1, "Change within debounce should be suppressed")
  }

  func test_directionChange_afterDebounce_fires() {
    let controller = makeController()
    let now = Date()

    let centerBox = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: centerBox, distance: nil, timestamp: now)

    // Change + wait past debounce (0.5s)
    let leftBox = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: leftBox, distance: nil, timestamp: now.addingTimeInterval(0.6))

    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("on your left"))
  }

  // MARK: - No "Still [direction]" repeat

  func test_noStillAnnouncement_forSameDirection() {
    let controller = makeController()
    let box = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.5)  // left
    let now = Date()

    controller.tick(targetBox: box, distance: nil, timestamp: now)

    // Many ticks later, same direction — must never say "Still on your left"
    for i in 1...5 {
      controller.tick(
        targetBox: box, distance: nil,
        timestamp: now.addingTimeInterval(Double(i) * 5.0))
    }

    XCTAssertEqual(mockSpeaker.speakCallCount, 1, "Repeat announcements for same direction must be suppressed")
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Still"))
  }

  // MARK: - Speech disabled

  func test_speechDisabled_noSpeech() {
    settings.enableSpeech = false
    let controller = makeController()

    let box = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)
    controller.tick(targetBox: box, distance: nil, timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Reset

  func test_reset_causesFirstDirectionToSpeakAgain() {
    let controller = makeController()
    let box = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)  // center
    let now = Date()

    controller.tick(targetBox: box, distance: nil, timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // After reset, same direction should speak again (new session)
    controller.reset()
    controller.tick(targetBox: box, distance: nil, timestamp: now.addingTimeInterval(1.0))
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
  }

  // MARK: - Distance parameter is accepted but not spoken

  func test_distanceProvided_notIncludedInSpeech() {
    let controller = makeController()
    let box = CGRect(x: 0.4, y: 0.0, width: 0.2, height: 0.5)

    controller.tick(targetBox: box, distance: 5.0, timestamp: Date())

    // Direction speech must not include distance — milestones own that
    XCTAssertFalse(
      mockSpeaker.spokenPhrases.contains(where: { $0.contains("meter") }),
      "Distance should not appear in direction speech")
  }
}
