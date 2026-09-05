//  NetworkFeedbackControllerTests.swift
//  thing-finderTests
//
//  Unit tests for NetworkFeedbackController.
//  Covers: pre-flight offline check, hard outage transitions (with distinct
//  lost/restored haptics), weak-signal transitions, and reset behavior.

import XCTest

@testable import thing_finder

final class NetworkFeedbackControllerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var mockHaptics: MockHapticManager!
  private var mockNetworkMonitor: MockNetworkMonitor!
  private var mockAPIHealthMonitor: MockAPIHealthMonitor!
  private var cache: AnnouncementCache!
  private var settings: Settings!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    mockHaptics = MockHapticManager()
    mockNetworkMonitor = MockNetworkMonitor(isConnected: true)
    mockAPIHealthMonitor = MockAPIHealthMonitor(isDegraded: false)
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
  }

  override func tearDown() {
    mockSpeaker = nil
    mockHaptics = nil
    mockNetworkMonitor = nil
    mockAPIHealthMonitor = nil
    cache = nil
    settings = nil
    super.tearDown()
  }

  private func makeController() -> NetworkFeedbackController {
    return NetworkFeedbackController(
      speaker: mockSpeaker,
      hapticManager: mockHaptics,
      cache: cache,
      settings: settings,
      networkMonitor: mockNetworkMonitor,
      apiHealthMonitor: mockAPIHealthMonitor
    )
  }

  // MARK: - Pre-flight check

  func test_preflight_onlineAtStart_noAnnouncement() {
    let controller = makeController()
    controller.tick(timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_preflight_offlineAtStart_announcesImmediately() {
    mockNetworkMonitor.isConnected = false
    let controller = makeController()
    controller.tick(timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("No internet connection"))
  }

  func test_preflight_firesOnlyOnce() {
    mockNetworkMonitor.isConnected = false
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    let offlineCount = mockSpeaker.spokenPhrases.filter { $0.contains("No internet connection") }
      .count
    XCTAssertEqual(offlineCount, 1)
  }

  // MARK: - Hard outage transitions

  func test_connectionLost_midSearch_announcesAndHaptics() {
    settings.enableHaptics = true
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight, online
    mockSpeaker.reset()

    mockNetworkMonitor.isConnected = false
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Connection lost"))
    XCTAssertEqual(mockHaptics.failureCallCount, 1)
  }

  func test_connectionRestored_announcesWithSuccessHaptic() {
    settings.enableHaptics = true
    mockNetworkMonitor.isConnected = false
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight, offline
    mockSpeaker.reset()
    mockHaptics.reset()

    mockNetworkMonitor.isConnected = true
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Connection restored"))
    // Distinct haptic from the "lost" case — success tap, not an error tap.
    XCTAssertEqual(mockHaptics.successCallCount, 1)
    XCTAssertEqual(mockHaptics.failureCallCount, 0)
  }

  func test_connectivity_doesNotReannounce_whenUnchanged() {
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)
    mockSpeaker.reset()

    controller.tick(timestamp: now.addingTimeInterval(1.0))
    controller.tick(timestamp: now.addingTimeInterval(2.0))

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Weak signal transitions

  func test_degraded_announcesWeakSignal_whenConnected() {
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight
    mockSpeaker.reset()

    mockAPIHealthMonitor.isDegraded = true
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Weak signal"))
  }

  func test_degraded_recoveryAnnounces() {
    let controller = makeController()
    let now = Date()

    mockAPIHealthMonitor.isDegraded = true
    controller.tick(timestamp: now)
    mockSpeaker.reset()

    mockAPIHealthMonitor.isDegraded = false
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Signal improved"))
  }

  func test_degraded_suppressed_duringHardOutage() {
    // A hard outage's own message is clearer — don't also announce "weak signal".
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight, online
    mockSpeaker.reset()

    mockNetworkMonitor.isConnected = false
    mockAPIHealthMonitor.isDegraded = true
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Connection lost"))
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Weak signal"))
  }

  func test_degraded_stillDegradedOnRestore_doesNotCutOffRestorationMessage() {
    // Regression: if API health became (and remains) degraded during a hard
    // outage, restoring the connection must not have "Weak signal" cut off
    // "Connection restored" — `Speaker.speak` cancels whatever is currently
    // playing, so both being spoken on the same tick would lose the
    // restoration message.
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight, online
    mockSpeaker.reset()

    // Outage begins; API health degrades while offline (state preserved,
    // not yet reflected in `lastKnownDegraded` since it's suppressed
    // during a hard outage).
    mockNetworkMonitor.isConnected = false
    mockAPIHealthMonitor.isDegraded = true
    controller.tick(timestamp: now.addingTimeInterval(1.0))
    mockSpeaker.reset()

    // Connection restored — API health is still degraded.
    mockNetworkMonitor.isConnected = true
    let restoreTime = now.addingTimeInterval(2.0)
    controller.tick(timestamp: restoreTime)

    XCTAssertEqual(
      mockSpeaker.speakCallCount, 1,
      "Only one phrase should speak this tick — weak signal must be deferred")
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Connection restored"))
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Weak signal"))

    // The still-degraded transition isn't lost — it announces on the next
    // tick, once it won't collide with another announcement.
    controller.tick(timestamp: restoreTime.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Weak signal"))
  }

  // MARK: - Settings gating

  func test_noSpeech_whenSpeechDisabled() {
    settings.enableSpeech = false
    mockNetworkMonitor.isConnected = false
    let controller = makeController()

    controller.tick(timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_noHaptic_whenHapticsDisabled() {
    settings.enableHaptics = false
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)  // pre-flight, online
    mockNetworkMonitor.isConnected = false
    controller.tick(timestamp: now.addingTimeInterval(1.0))
    mockNetworkMonitor.isConnected = true
    controller.tick(timestamp: now.addingTimeInterval(2.0))

    XCTAssertEqual(mockHaptics.failureCallCount, 0)
    XCTAssertEqual(mockHaptics.successCallCount, 0)
  }

  func test_newSession_ignoresDegradationFromPreviousSearch() {
    // The health monitor is shared across searches: a search that ended while
    // degraded must not make the next one announce "Weak signal" before it has
    // issued a single request.
    mockAPIHealthMonitor.isDegraded = true
    let controller = makeController()

    controller.tick(timestamp: Date())

    XCTAssertEqual(mockAPIHealthMonitor.resetCallCount, 1)
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Weak signal"))
  }

  // MARK: - Reset

  func test_reset_allowsPreflightToFireAgain() {
    mockNetworkMonitor.isConnected = false
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)
    mockSpeaker.reset()

    controller.reset()
    controller.tick(timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("No internet connection"))
  }

  func test_reset_clearsAPIHealthState() {
    let controller = makeController()

    mockAPIHealthMonitor.isDegraded = true
    controller.reset()

    XCTAssertFalse(mockAPIHealthMonitor.isDegraded)
  }

  // MARK: - Frame priority

  func test_announcement_claimsFrameSoOtherControllersDefer() {
    mockNetworkMonitor.isConnected = false
    let controller = makeController()
    let now = Date()

    controller.tick(timestamp: now)

    XCTAssertTrue(cache.isFramePreempted(now))
  }
}
