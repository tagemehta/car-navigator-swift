//  NavAnnouncerTests.swift
//  thing-finderTests
//
//  Unit tests for NavAnnouncer speech announcement logic.
//
//  Ownership boundary
//  ──────────────────
//  NavAnnouncer handles: full / partial / lost status transitions + vehicle view.
//  PreMatchFeedbackController handles: session-start, heartbeat, earcon, rejections.

import XCTest

@testable import thing_finder

final class NavAnnouncerTests: XCTestCase {

  private var mockSpeaker: MockSpeechOutput!
  private var mockHaptics: MockHapticManager!
  private var mockCompass: MockCompassProvider!
  private var cache: AnnouncementCache!
  private var settings: Settings!
  private var config: NavigationFeedbackConfig!

  override func setUp() {
    super.setUp()
    mockSpeaker = MockSpeechOutput()
    mockHaptics = MockHapticManager()
    mockCompass = MockCompassProvider(degrees: 0.0)
    cache = AnnouncementCache()
    settings = TestSettings.makeDefault()
    config = NavigationFeedbackConfig(
      speechRepeatInterval: 6.0,
      directionChangeInterval: 4.0,
      retryPhraseCooldown: 8.0
    )
  }

  override func tearDown() {
    mockSpeaker = nil
    mockHaptics = nil
    mockCompass = nil
    cache = nil
    settings = nil
    config = nil
    super.tearDown()
  }

  private func makeAnnouncer() -> NavAnnouncer {
    return NavAnnouncer(
      cache: cache,
      config: config,
      speaker: mockSpeaker,
      hapticManager: mockHaptics,
      compass: mockCompass,
      settings: settings
    )
  }

  // MARK: - Speech Enable/Disable

  func test_tick_noSpeechWhenDisabled() {
    settings.enableSpeech = false
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_tick_speaksWhenEnabled() {
    settings.enableSpeech = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertGreaterThan(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Status Transition Announcements

  func test_tick_announcesFullMatchWithPlate() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full
    candidate.ocrText = "ABC1234"

    announcer.tick(candidates: [candidate], timestamp: Date())

    // New phrase: "Found it — plate ABC1234"
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Found it"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("ABC1234"))
  }

  func test_tick_announcesFullMatchWithoutPlate() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full
    candidate.ocrText = nil

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Found it"))
  }

  func test_tick_announcesPartialMatch() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .partial

    announcer.tick(candidates: [candidate], timestamp: Date())

    // New phrase: "Possible match — plate not visible" (no description)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Possible match"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("plate not visible"))
  }

  func test_tick_announcesPartialToFullTransition() {
    // On partial→full upgrade, NavAnnouncer should speak the transition phrase
    // ("Plate confirmed") rather than the generic "Found it".
    let announcer = makeAnnouncer()
    let id = UUID()

    var candidate = TestCandidates.make(id: id)
    candidate.matchStatus = .partial

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Possible match"))

    // Upgrade to full
    candidate.matchStatus = .full
    candidate.ocrText = "XYZ789"
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Plate confirmed"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("XYZ789"))
    // Should NOT announce the generic "Found it" since the transition phrase was used
    XCTAssertFalse(mockSpeaker.didSpeak("Found it"))
  }

  func test_tick_announcesPartialToFullTransition_noPlate() {
    let announcer = makeAnnouncer()
    let id = UUID()

    var candidate = TestCandidates.make(id: id)
    candidate.matchStatus = .partial

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)

    candidate.matchStatus = .full
    candidate.ocrText = nil
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(1.0))

    XCTAssertTrue(mockSpeaker.didSpeak("Got it"))
  }

  func test_tick_noSpeechForWaitingStatus() {
    // Waiting is now silent — earcon handles evaluation feedback.
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .waiting

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_tick_noSpeechForRejectedStatus() {
    // Rejected is handled by PreMatchFeedbackController, not NavAnnouncer.
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .rejected
    candidate.rejectReason = .wrongModelOrColor

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_tick_noAnnouncementForUnknownStatus() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .unknown

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Candidate Priority

  func test_tick_prefersFullOverPartial() {
    let announcer = makeAnnouncer()

    var fullCandidate = TestCandidates.make(id: UUID())
    fullCandidate.matchStatus = .full
    fullCandidate.ocrText = "FULL123"

    var partialCandidate = TestCandidates.make(id: UUID())
    partialCandidate.matchStatus = .partial

    announcer.tick(candidates: [partialCandidate, fullCandidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("FULL123"))
    XCTAssertFalse(mockSpeaker.didSpeakContaining("Possible match"))
  }

  // MARK: - Cooldown Behavior

  func test_tick_suppressesRepeatPhrase() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full
    candidate.ocrText = "ABC1234"

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    let firstCount = mockSpeaker.speakCallCount

    // Tick again immediately — should be suppressed (status unchanged)
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))

    XCTAssertEqual(mockSpeaker.speakCallCount, firstCount)
  }

  func test_tick_speaksAfterStatusChange() {
    let announcer = makeAnnouncer()
    let candidateId = UUID()

    var candidate = TestCandidates.make(id: candidateId)
    candidate.matchStatus = .partial

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Change to full — should announce (transition phrase)
    candidate.matchStatus = .full
    candidate.ocrText = nil
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
  }

  // MARK: - Status Change Detection

  func test_tick_announcesOnStatusChange() {
    let announcer = makeAnnouncer()
    let candidateId = UUID()

    var candidate = TestCandidates.make(id: candidateId)
    candidate.matchStatus = .partial

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    let countAfterPartial = mockSpeaker.speakCallCount

    // Change status to full
    candidate.matchStatus = .full
    candidate.ocrText = "XYZ789"
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))

    XCTAssertGreaterThan(mockSpeaker.speakCallCount, countAfterPartial)
  }

  // MARK: - Empty Candidates

  func test_tick_handlesEmptyCandidates() {
    let announcer = makeAnnouncer()

    announcer.tick(candidates: [], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Lost Candidate Routing

  func test_tick_announcesLostCandidateWithSignificantAngle() {
    mockCompass.degrees = 90.0
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.makeLost()
    candidate.degrees = 0.0

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("degrees to the right"))
  }

  func test_tick_doesNotAnnounceLostWithSmallAngle() {
    mockCompass.degrees = 30.0
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.makeLost()
    candidate.degrees = 0.0

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_tick_lostCandidatesAlwaysEligibleRegardlessOfPriority() {
    mockCompass.degrees = 120.0
    let announcer = makeAnnouncer()

    var fullCandidate = TestCandidates.make(id: UUID())
    fullCandidate.matchStatus = .full
    fullCandidate.ocrText = "ABC123"

    var lostCandidate = TestCandidates.makeLost(id: UUID())
    lostCandidate.degrees = 0.0

    announcer.tick(
      candidates: [fullCandidate, lostCandidate],
      timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("ABC123"))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("degrees"))
  }

  // MARK: - Haptic Transitions

  func test_tick_playsSuccessHapticOnFullMatch() {
    settings.enableHaptics = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockHaptics.successCallCount, 1)
  }

  func test_tick_noFailureHapticForRejected() {
    settings.enableHaptics = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .rejected
    candidate.rejectReason = .wrongModelOrColor

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockHaptics.failureCallCount, 0)
  }

  func test_tick_noHapticsWhenDisabled() {
    settings.enableHaptics = false
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockHaptics.successCallCount, 0)
    XCTAssertEqual(mockHaptics.failureCallCount, 0)
  }

  // MARK: - Candidate Eviction

  func test_tick_prunesStaleTrackingState() {
    let announcer = makeAnnouncer()
    let candidateId = UUID()

    var candidate = TestCandidates.make(id: candidateId)
    candidate.matchStatus = .full

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertNotNil(cache.lastByCandidate[candidateId])

    announcer.tick(candidates: [], timestamp: now.addingTimeInterval(1.0))
    XCTAssertNil(cache.lastByCandidate[candidateId])
  }

  // MARK: - Vehicle View Announcements

  func test_tick_announcesVehicleViewOnce() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make(matchStatus: .full, view: .front)
    candidate.ocrText = "ABC123"

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Front view of car"))

    let beforeCount = mockSpeaker.speakCallCount
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(7.0))
    XCTAssertFalse(
      mockSpeaker.spokenPhrases.suffix(from: beforeCount).contains(where: {
        $0.contains("Front view of car")
      }),
      "View should not be re-announced when unchanged")
  }

  func test_tick_reAnnouncesViewOnChange() {
    let announcer = makeAnnouncer()
    let id = UUID()

    var candidate = TestCandidates.make(id: id, matchStatus: .full, view: .front)
    candidate.ocrText = "ABC123"

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Front view of car"))

    candidate.view = .rear
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(7.0))
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Rear view of car"))
  }

  func test_tick_doesNotAnnounceUnknownView() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make(matchStatus: .full, view: .unknown)
    candidate.ocrText = "ABC123"

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertFalse(mockSpeaker.didSpeakContaining("of car"))
  }

  func test_tick_evictionClearsViewTracking() {
    let announcer = makeAnnouncer()
    let id = UUID()

    var candidate = TestCandidates.make(id: id, matchStatus: .full, view: .left)
    candidate.ocrText = "ABC123"

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertTrue(mockSpeaker.didSpeakContaining("Left side of car"))

    announcer.tick(candidates: [], timestamp: now.addingTimeInterval(1.0))

    mockSpeaker.reset()
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(8.0))
    XCTAssertTrue(
      mockSpeaker.didSpeakContaining("Left side of car"),
      "After eviction, view should be re-announced")
  }

  // MARK: - Timestamp-based Cooldown

  func test_tick_cooldownUsesPassedTimestamp() {
    let announcer = makeAnnouncer()

    var c1 = TestCandidates.make(id: UUID())
    c1.matchStatus = .full
    c1.ocrText = "SAME"

    var c2 = TestCandidates.make(id: UUID())
    c2.matchStatus = .full
    c2.ocrText = "SAME"

    let base = Date(timeIntervalSince1970: 1_000_000)

    announcer.tick(candidates: [c1, c2], timestamp: base)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    announcer.tick(candidates: [c1, c2], timestamp: base.addingTimeInterval(1.0))
    XCTAssertEqual(mockSpeaker.speakCallCount, 1, "Status unchanged should suppress")
  }
}
