//  PreMatchFeedbackControllerTests.swift
//  thing-finderTests
//
//  Unit tests for PreMatchFeedbackController.
//  Covers: session-start, detection haptics, heartbeat, rejection announcements,
//  high-density grouped fallback, and dormancy when a match exists.

import XCTest

@testable import thing_finder

final class PreMatchFeedbackControllerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var mockHaptics: MockHapticManager!
  private var cache: AnnouncementCache!
  private var settings: Settings!
  private var config: NavigationFeedbackConfig!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    mockHaptics = MockHapticManager()
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
    // Short intervals so tests don't need to advance time by 20s.
    config = NavigationFeedbackConfig(
      speechRepeatInterval: 6.0,
      directionChangeInterval: 4.0,
      retryPhraseCooldown: 8.0
    )
    config.detectionHapticStabilityGate = 0.3
    config.detectionHapticCooldown = 0.5
    config.scanningHeartbeatInterval = 5.0
    config.rejectionCooldown = 1.0
    config.rejectionDensityWindow = 10.0
    config.rejectionDensityLimit = 3
  }

  override func tearDown() {
    mockSpeaker = nil
    mockHaptics = nil
    cache = nil
    settings = nil
    config = nil
    super.tearDown()
  }

  private func makeController(description: String = "blue Honda Prius")
    -> PreMatchFeedbackController
  {
    return PreMatchFeedbackController(
      speaker: mockSpeaker,
      hapticManager: mockHaptics,
      cache: cache,
      config: config,
      settings: settings,
      targetDescription: description
    )
  }

  // MARK: - Session Start

  func test_sessionStart_speaksSearchingPhrase() {
    let controller = makeController(description: "red Toyota")

    controller.tick(candidates: [], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("red Toyota"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Searching for"))
  }

  func test_sessionStart_firesOnlyOnce() {
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(1.0))

    let searchCount = mockSpeaker.spokenPhrases.filter { $0.contains("Searching for") }.count
    XCTAssertEqual(searchCount, 1)
  }

  func test_sessionStart_refires_afterReset() {
    let controller = makeController(description: "blue Honda")
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    controller.reset()
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(1.0))

    let searchCount = mockSpeaker.spokenPhrases.filter { $0.contains("Searching for") }.count
    XCTAssertEqual(searchCount, 2)
  }

  func test_sessionStart_silentWhenSpeechDisabled() {
    settings.enableSpeech = false
    let controller = makeController()

    controller.tick(candidates: [], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_sessionStart_deferredWhenAnotherControllerSpokeSameTick() {
    // Regression: `NetworkFeedbackController` runs earlier in the same
    // `FrameNavigationManager.tick()` call and, on a cold offline start,
    // speaks a connectivity warning using the same `timestamp`. Since
    // `Speaker.speak` cancels whatever is currently playing, the session
    // start announcement must not immediately speak over it.
    let controller = makeController(description: "red Toyota")
    let now = Date()

    // Simulate NetworkFeedbackController having already spoken this tick.
    cache.lastGlobal = (phrase: "No internet connection — search may not work", time: now)

    controller.tick(candidates: [], timestamp: now)

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Searching for"))
  }

  func test_sessionStart_firesOnNextTick_afterDeferral() {
    let controller = makeController(description: "red Toyota")
    let now = Date()

    // First tick: deferred because another controller already spoke.
    cache.lastGlobal = (phrase: "No internet connection — search may not work", time: now)
    controller.tick(candidates: [], timestamp: now)
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Searching for"))

    // Next tick: nothing new was spoken at this later timestamp, so session
    // start proceeds normally.
    let next = now.addingTimeInterval(0.05)
    controller.tick(candidates: [], timestamp: next)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Searching for"))
  }

  // MARK: - Detection haptics

  func test_detectionHaptic_firesAfterStabilityGate() {
    settings.enableHaptics = true
    let controller = makeController()
    let now = Date()
    let candidate = TestCandidates.make(id: UUID())

    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))
    XCTAssertEqual(mockHaptics.detectionCallCount, 0)

    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.5))
    XCTAssertEqual(mockHaptics.detectionCallCount, 1)
  }

  func test_detectionHaptic_doesNotRefireForSameCandidate() {
    settings.enableHaptics = true
    let controller = makeController()
    let now = Date()
    let candidate = TestCandidates.make(id: UUID())

    controller.tick(candidates: [candidate], timestamp: now)
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(1.0))
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(2.0))

    XCTAssertEqual(mockHaptics.detectionCallCount, 1)
  }

  func test_detectionHaptic_coolsDownBetweenNearbyCars() {
    settings.enableHaptics = true
    let controller = makeController()
    let now = Date()
    let first = TestCandidates.make(id: UUID())
    let second = TestCandidates.make(id: UUID())

    controller.tick(candidates: [first, second], timestamp: now)
    controller.tick(candidates: [first, second], timestamp: now.addingTimeInterval(0.3))
    XCTAssertEqual(mockHaptics.detectionCallCount, 1)

    controller.tick(candidates: [first, second], timestamp: now.addingTimeInterval(0.8))
    XCTAssertEqual(mockHaptics.detectionCallCount, 2)
  }

  func test_detectionHaptic_isSuppressedWhenDisabled() {
    settings.enableHaptics = false
    let controller = makeController()
    let now = Date()
    let candidate = TestCandidates.make(id: UUID())

    controller.tick(candidates: [candidate], timestamp: now)
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(1.0))

    XCTAssertEqual(mockHaptics.detectionCallCount, 0)
  }

  func test_detectionHaptic_isSuppressedWhenMatchExists() {
    settings.enableHaptics = true
    let controller = makeController()
    var candidate = TestCandidates.make(id: UUID())
    candidate.matchStatus = .partial

    controller.tick(candidates: [candidate], timestamp: Date().addingTimeInterval(1.0))

    XCTAssertEqual(mockHaptics.detectionCallCount, 0)
  }

  // MARK: - Heartbeat

  func test_heartbeat_firesAfterInterval_whenNoCandidates() {
    let controller = makeController()
    let now = Date()

    // First tick fires session-start; clear cache to not block heartbeat.
    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Advance past heartbeat interval (5s in tests)
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(6.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Still looking"))
  }

  func test_heartbeat_doesNotFire_whenCandidatesExist() {
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Tick with a candidate — heartbeat should be suppressed
    let candidate = TestCandidates.make()
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(6.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Still looking"))
  }

  func test_heartbeat_doesNotFire_beforeInterval() {
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Only 2 seconds later — below the 5s threshold
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(2.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Still looking"))
  }

  func test_heartbeat_respectsAnnounceWaitingMessagesSetting() {
    // When announceWaitingMessages is false, heartbeat should be suppressed.
    settings.announceWaitingMessages = false
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Advance past heartbeat interval
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(6.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Still looking"))
  }

  func test_heartbeat_firesWhenAnnounceWaitingMessagesEnabled() {
    // When announceWaitingMessages is true, heartbeat should fire.
    settings.announceWaitingMessages = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Advance past heartbeat interval
    controller.tick(candidates: [], timestamp: now.addingTimeInterval(6.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Still looking"))
  }

  // MARK: - Rejection Announcements

  func test_rejection_respectsAnnounceRejectedSetting() {
    // When announceRejected is false, rejections should be suppressed.
    settings.announceRejected = false
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    var candidate = TestCandidates.makeRejected()
    candidate.detectedDescription = "red Toyota"

    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(2.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Not yours"))
  }

  func test_rejection_announcesWhenAnnounceRejectedEnabled() {
    // When announceRejected is true, rejections should fire.
    settings.announceRejected = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    var candidate = TestCandidates.makeRejected()
    candidate.detectedDescription = "red Toyota"

    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(2.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Not yours"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("red Toyota"))
  }

  func test_rejection_announcedOnlyOnce_perCandidate() {
    settings.announceRejected = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    var candidate = TestCandidates.makeRejected()
    candidate.detectedDescription = "red Toyota"

    // First tick — announces
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(2.0))
    let countAfterFirst = mockSpeaker.speakCallCount

    // Second tick with same candidate — must not re-announce
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(5.0))
    XCTAssertEqual(mockSpeaker.speakCallCount, countAfterFirst)
  }

  func test_rejection_respectsCooldown() {
    settings.announceRejected = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()

    // Seed cache.lastGlobal to simulate a recent speech event
    cache.lastGlobal = (phrase: "prior speech", time: now.addingTimeInterval(2.0))

    var candidate = TestCandidates.makeRejected()
    candidate.detectedDescription = "blue Ford"

    // Tick immediately after recent speech — within rejectionCooldown (1.0s)
    controller.tick(
      candidates: [candidate],
      timestamp: now.addingTimeInterval(2.5))

    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "Rejection should be suppressed within cooldown")
  }

  func test_rejection_retriesAfterCooldownExpires() {
    // Regression: a candidate suppressed by the global cooldown must remain
    // eligible and speak once the cooldown window passes.
    settings.announceRejected = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()

    // Seed a recent speech event so the cooldown is active.
    cache.lastGlobal = (phrase: "prior speech", time: now.addingTimeInterval(2.0))

    var candidate = TestCandidates.makeRejected()
    candidate.detectedDescription = "blue Ford"

    // Tick within cooldown — should be suppressed, not permanently marked.
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(2.5))
    XCTAssertEqual(mockSpeaker.speakCallCount, 0, "Should be suppressed within cooldown")

    // Tick after cooldown expires (rejectionCooldown = 1.0s, so 2.0s gap is safe).
    controller.tick(candidates: [candidate], timestamp: now.addingTimeInterval(4.5))
    XCTAssertTrue(
      mockSpeaker.didSpeakContaining("blue Ford"),
      "Candidate should announce once cooldown expires")
  }

  func test_rejection_groupedRetries_afterGroupedCooldownExpires() {
    // Regression: a candidate that triggers high-density mode but is suppressed
    // by the grouped-phrase cooldown must remain eligible and speak once
    // lastGroupedRejectionTime is sufficiently old.
    //
    // We use rejectionDensityWindow = 30s (wider than the 10s grouped cooldown)
    // so the density buffer remains full throughout the test.
    //
    // Timeline:
    //   t=0   fill buffer (3 fillers) — timestamps recorded at t=1s
    //   t=1   overflow1 fires grouped phrase; lastGroupedRejectionTime = t=1
    //   t=6   overflow2 suppressed (5s < 10s grouped cooldown)
    //   t=12  overflow2 fires — grouped cooldown expired, buffer still full (timestamps 11s old < 30s)
    settings.announceRejected = true
    config.rejectionDensityWindow = 30.0

    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Fill the density buffer to the limit.
    let density = config.rejectionDensityLimit
    for i in 0..<density {
      var filler = TestCandidates.makeRejected(id: UUID())
      filler.detectedDescription = "filler \(i)"
      cache.lastGlobal = nil
      controller.tick(candidates: [filler], timestamp: now.addingTimeInterval(1.0))
    }

    // overflow1 — density limit met; first grouped phrase fires.
    var overflow1 = TestCandidates.makeRejected(id: UUID())
    overflow1.detectedDescription = "overflow 1"
    cache.lastGlobal = nil
    let t1 = now.addingTimeInterval(1.0)
    controller.tick(candidates: [overflow1], timestamp: t1)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Several cars nearby"))

    // overflow2 — grouped cooldown (10s) still active at t1+5s; must be suppressed.
    var overflow2 = TestCandidates.makeRejected(id: UUID())
    overflow2.detectedDescription = "overflow 2"
    cache.lastGlobal = nil
    mockSpeaker.reset()
    controller.tick(candidates: [overflow2], timestamp: t1.addingTimeInterval(5.0))
    XCTAssertFalse(
      mockSpeaker.didSpeakContaining("Several cars nearby"),
      "Grouped phrase should be suppressed within grouped cooldown")

    // overflow2 again at t1+11s — grouped cooldown (10s) expired.
    // Filler timestamps are at now+1 = t1; t1+11 - t1 = 11s < 30s window → buffer still full.
    cache.lastGlobal = nil
    controller.tick(candidates: [overflow2], timestamp: t1.addingTimeInterval(11.0))
    XCTAssertTrue(
      mockSpeaker.didSpeakContaining("Several cars nearby"),
      "Grouped phrase should fire once grouped cooldown expires")
  }

  // MARK: - High-Density Grouped Fallback

  func test_rejection_groupsWhenDensityExceeded() {
    settings.announceRejected = true
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    // Populate density buffer with 3 recent rejections (equal to the limit).
    // We do this by advancing time and using distinct candidates.
    let density = config.rejectionDensityLimit
    var rejectedCandidates: [Candidate] = (0..<density).map { i in
      var c = TestCandidates.makeRejected(id: UUID())
      c.detectedDescription = "car \(i)"
      return c
    }

    // Each candidate is announced one at a time, respecting cooldown.
    for (i, candidate) in rejectedCandidates.enumerated() {
      cache.lastGlobal = nil
      controller.tick(
        candidates: [candidate],
        timestamp: now.addingTimeInterval(Double(i + 1) * 2.0))
    }

    // Now add a 4th candidate — density limit exceeded, should get grouped phrase.
    var groupCandidate = TestCandidates.makeRejected(id: UUID())
    groupCandidate.detectedDescription = "car overflow"
    cache.lastGlobal = nil

    controller.tick(
      candidates: rejectedCandidates + [groupCandidate],
      timestamp: now.addingTimeInterval(Double(density + 1) * 2.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Several cars nearby"))
  }

  // MARK: - Dormancy When Match Exists

  func test_dormant_noHeartbeat_whenMatchExists() {
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    var matchedCandidate = TestCandidates.make()
    matchedCandidate.matchStatus = .full

    controller.tick(candidates: [matchedCandidate], timestamp: now.addingTimeInterval(6.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Still looking"))
  }

  func test_dormant_noRejection_whenMatchExists() {
    let controller = makeController()
    let now = Date()

    controller.tick(candidates: [], timestamp: now)
    mockSpeaker.reset()
    cache.lastGlobal = nil

    var matchedCandidate = TestCandidates.make()
    matchedCandidate.matchStatus = .partial

    var rejectedCandidate = TestCandidates.makeRejected()
    rejectedCandidate.detectedDescription = "red Toyota"

    controller.tick(
      candidates: [matchedCandidate, rejectedCandidate],
      timestamp: now.addingTimeInterval(2.0))

    XCTAssertFalse(mockSpeaker.didSpeakContaining("Not yours"))
  }
}
