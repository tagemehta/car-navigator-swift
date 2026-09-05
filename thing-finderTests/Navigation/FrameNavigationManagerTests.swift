//  FrameNavigationManagerTests.swift
//  thing-finderTests
//
//  Integration tests for `FrameNavigationManager`'s controller ordering.
//  Covers the interaction between `NetworkFeedbackController` and
//  `PreMatchFeedbackController` on a cold, offline session start.

import XCTest

@testable import thing_finder

final class FrameNavigationManagerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var mockHaptics: MockHapticManager!
  private var mockNetworkMonitor: MockNetworkMonitor!
  private var mockHealthMonitor: MockAPIHealthMonitor!
  private var settings: Settings!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    mockHaptics = MockHapticManager()
    mockNetworkMonitor = MockNetworkMonitor(isConnected: true)
    mockHealthMonitor = MockAPIHealthMonitor()
    settings = TestSettings.makeDefault()
  }

  override func tearDown() {
    mockSpeaker = nil
    mockHaptics = nil
    mockNetworkMonitor = nil
    mockHealthMonitor = nil
    settings = nil
    super.tearDown()
  }

  private func makeManager(description: String = "blue Honda Prius") -> FrameNavigationManager {
    FrameNavigationManager(
      settings: settings,
      targetDescription: description,
      speaker: mockSpeaker,
      hapticManager: mockHaptics,
      networkMonitor: mockNetworkMonitor,
      apiHealthMonitor: mockHealthMonitor
    )
  }

  /// Regression: on a cold offline start, `NetworkFeedbackController` (which
  /// runs first in `tick()`) speaks a connectivity warning using the same
  /// `timestamp` that gets passed to `PreMatchFeedbackController` right
  /// after. `Speaker.speak` cancels whatever is currently playing, so the
  /// session-start phrase must not immediately speak over the connectivity
  /// warning on that same tick — it should defer to the next tick instead.
  func test_offlineColdStart_connectivityWarningIsNotImmediatelyCancelled() {
    mockNetworkMonitor.isConnected = false
    let manager = makeManager(description: "red Toyota")
    let now = Date()

    manager.tick(at: now, candidates: [], targetBox: nil, distance: nil)

    XCTAssertTrue(
      mockSpeaker.didSpeakContaining("No internet connection"),
      "Connectivity warning should be spoken on the first offline tick")
    XCTAssertFalse(
      mockSpeaker.didSpeakContaining("Searching for"),
      "Session-start phrase must be deferred, not spoken over the connectivity warning")

    // Next tick: the network warning doesn't re-fire (state unchanged), so
    // session-start proceeds normally.
    manager.tick(
      at: now.addingTimeInterval(0.05), candidates: [], targetBox: nil, distance: nil)

    XCTAssertTrue(
      mockSpeaker.didSpeakContaining("Searching for"),
      "Session-start phrase should fire on the next tick once it's not competing with a warning")
  }

  /// The normal (online) path is unaffected: session-start speaks
  /// immediately on the first tick since no connectivity warning preempts it.
  func test_onlineColdStart_sessionStartSpeaksImmediately() {
    mockNetworkMonitor.isConnected = true
    let manager = makeManager(description: "red Toyota")

    manager.tick(at: Date(), candidates: [], targetBox: nil, distance: nil)

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Searching for"))
    XCTAssertFalse(mockSpeaker.didSpeakContaining("No internet connection"))
  }
}
