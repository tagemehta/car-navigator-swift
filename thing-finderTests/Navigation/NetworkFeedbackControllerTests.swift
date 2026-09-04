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
    mockAPIHealthMonitor.isDegraded = true
    let controller = makeController()
    let now = Date()

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
}
