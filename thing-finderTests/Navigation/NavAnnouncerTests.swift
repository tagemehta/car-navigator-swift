//  NavAnnouncerTests.swift
//  thing-finderTests
//
//  Unit tests for NavAnnouncer speech announcement logic.

import XCTest

@testable import thing_finder

final class NavAnnouncerTests: XCTestCase {

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
  }

  override func tearDown() {
    mockSpeaker = nil
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

    XCTAssertTrue(mockSpeaker.didSpeakContaining("ABC1234"))
  }

  func test_tick_announcesFullMatchWithDescription() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .full
    candidate.detectedDescription = "blue Honda Civic"

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("blue Honda Civic"))
  }

  func test_tick_announcesPartialMatch() {
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .partial
    candidate.detectedDescription = "blue Honda"

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Plate not visible"))
  }

  func test_tick_announcesWaitingStatus() {
    // Waiting is now controlled by announceWaitingMessages setting
    settings.announceWaitingMessages = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .waiting

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeak("Waiting for verification"))
  }

  func test_tick_noWaitingWhenDisabled() {
    settings.announceWaitingMessages = false
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .waiting

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertFalse(mockSpeaker.didSpeak("Waiting for verification"))
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
    partialCandidate.detectedDescription = "partial car"

    announcer.tick(candidates: [partialCandidate, fullCandidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("FULL123"))
    XCTAssertFalse(mockSpeaker.didSpeakContaining("partial car"))
  }

  func test_tick_announcesRejectedOnlyWhenEnabled() {
    settings.announceRejected = false
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .rejected
    candidate.rejectReason = .wrongModelOrColor

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }

  func test_tick_announcesRejectedWhenEnabled() {
    settings.announceRejected = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .rejected
    candidate.rejectReason = .wrongModelOrColor
    candidate.detectedDescription = "red Toyota"

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertGreaterThan(mockSpeaker.speakCallCount, 0)
  }

  // MARK: - Retry Announcements
  // Retry announcements are now controlled by announceRetryMessages setting

  func test_tick_announcesRetryForBlurryImage() {
    settings.announceRetryMessages = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .unknown
    candidate.rejectReason = .unclearImage

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("blurry"))
  }

  func test_tick_announcesRetryForInsufficientInfo() {
    settings.announceRetryMessages = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .unknown
    candidate.rejectReason = .insufficientInfo

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("better view"))
  }

  func test_tick_announcesRetryForLowConfidence() {
    settings.announceRetryMessages = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .unknown
    candidate.rejectReason = .lowConfidence

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertTrue(mockSpeaker.didSpeakContaining("Not sure"))
  }

  func test_tick_noRetryWhenDisabled() {
    settings.announceRetryMessages = false
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .unknown
    candidate.rejectReason = .unclearImage

    announcer.tick(candidates: [candidate], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
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

    // Tick again immediately - should be suppressed
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))

    XCTAssertEqual(mockSpeaker.speakCallCount, firstCount)
  }

  func test_tick_respectsWaitingCooldown() {
    settings.announceWaitingMessages = true
    let announcer = makeAnnouncer()

    var candidate = TestCandidates.make()
    candidate.matchStatus = .waiting

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Tick again within cooldown - should be suppressed
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(1.0))
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)
  }

  func test_tick_speaksAfterCooldownExpires() {
    // Use full match status which doesn't require announceRejected
    // and test that status changes trigger new announcements
    let announcer = makeAnnouncer()
    let candidateId = UUID()

    var candidate = TestCandidates.make(id: candidateId)
    candidate.matchStatus = .full
    candidate.ocrText = "ABC123"

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    XCTAssertEqual(mockSpeaker.speakCallCount, 1)

    // Change to different status - should announce
    candidate.matchStatus = .partial
    candidate.ocrText = nil
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))
    XCTAssertEqual(mockSpeaker.speakCallCount, 2)
  }

  // MARK: - Status Change Detection

  func test_tick_announcesOnStatusChange() {
    let announcer = makeAnnouncer()
    let candidateId = UUID()

    var candidate = TestCandidates.make(id: candidateId)
    candidate.matchStatus = .waiting

    let now = Date()
    announcer.tick(candidates: [candidate], timestamp: now)
    let countAfterWaiting = mockSpeaker.speakCallCount

    // Change status to full
    candidate.matchStatus = .full
    candidate.ocrText = "XYZ789"
    announcer.tick(candidates: [candidate], timestamp: now.addingTimeInterval(0.1))

    XCTAssertGreaterThan(mockSpeaker.speakCallCount, countAfterWaiting)
  }

  // MARK: - Empty Candidates

  func test_tick_handlesEmptyCandidates() {
    let announcer = makeAnnouncer()

    announcer.tick(candidates: [], timestamp: Date())

    XCTAssertEqual(mockSpeaker.speakCallCount, 0)
  }
}
