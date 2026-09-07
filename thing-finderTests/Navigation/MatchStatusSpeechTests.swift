//  MatchStatusSpeechTests.swift
//  thing-finderTests
//
//  Unit tests for MatchStatusSpeech phrase and transition phrase generation.

import XCTest

@testable import thing_finder

final class MatchStatusSpeechTests: XCTestCase {

  // MARK: - Waiting Status
  // Waiting is now silent — no feedback while a candidate is being evaluated.

  func test_phrase_waiting_returnsNil() {
    XCTAssertNil(MatchStatusSpeech.phrase(for: .waiting))
  }

  // MARK: - Full Match Status

  func test_phrase_fullWithPlate_returnsFoundItWithPlate() {
    let phrase = MatchStatusSpeech.phrase(for: .full, recognisedText: "ABC1234")

    XCTAssertEqual(phrase, "Found it \u{2014} plate ABC1234")
  }

  func test_phrase_fullWithoutPlate_returnsFoundIt() {
    // detectedDescription is no longer part of the full-match phrase.
    let phrase = MatchStatusSpeech.phrase(for: .full, recognisedText: nil)

    XCTAssertEqual(phrase, "Found it")
  }

  // MARK: - Partial Match Status

  func test_phrase_partial_returnsPossibleMatchPlateNotVisible() {
    // Partial always returns the same phrase regardless of description.
    let phrase = MatchStatusSpeech.phrase(for: .partial)

    XCTAssertEqual(phrase, "Possible match \u{2014} plate not visible")
  }

  // MARK: - Rejected Status
  // Rejected is now silent — PreMatchFeedbackController owns rejection announcements.

  func test_phrase_rejected_returnsNil() {
    XCTAssertNil(MatchStatusSpeech.phrase(for: .rejected))
  }

  // MARK: - Unknown Status

  func test_phrase_unknown_returnsNil() {
    XCTAssertNil(MatchStatusSpeech.phrase(for: .unknown))
  }

  // MARK: - Lost Status

  func test_phrase_lost_withSmallAngleChange_returnsNil() {
    let phrase = MatchStatusSpeech.phrase(for: .lost, lastDirection: 0.0, currentHeading: 30.0)

    XCTAssertNil(phrase)
  }

  func test_phrase_lost_withLargeRightAngle_returnsRightDirection() {
    let phrase = MatchStatusSpeech.phrase(for: .lost, lastDirection: 0.0, currentHeading: 90.0)

    XCTAssertNotNil(phrase)
    XCTAssertTrue(phrase!.contains("degrees to the right"))
  }

  func test_phrase_lost_withLargeLeftAngle_returnsLeftDirection() {
    let phrase = MatchStatusSpeech.phrase(for: .lost, lastDirection: 90.0, currentHeading: 0.0)

    XCTAssertNotNil(phrase)
    XCTAssertTrue(phrase!.contains("degrees to the left"))
  }

  // MARK: - Retry Phrases (legacy — always nil)

  func test_retryPhrase_allReasonsReturnNil() {
    let reasons: [RejectReason] = [
      .unclearImage, .insufficientInfo, .lowConfidence,
      .apiError, .licensePlateNotVisible, .ambiguous,
      .wrongModelOrColor, .success,
    ]
    for reason in reasons {
      XCTAssertNil(
        MatchStatusSpeech.retryPhrase(for: reason),
        "Expected nil for \(reason)")
    }
  }

  // MARK: - Transition Phrases (partial → full)

  func test_transitionPhrase_partialToFullWithPlate_returnsPlateConfirmed() {
    let phrase = MatchStatusSpeech.transitionPhrase(
      from: .partial, to: .full, recognisedText: "XYZ789")

    XCTAssertEqual(phrase, "Plate confirmed \u{2014} XYZ789")
  }

  func test_transitionPhrase_partialToFullWithoutPlate_returnsGotIt() {
    let phrase = MatchStatusSpeech.transitionPhrase(
      from: .partial, to: .full, recognisedText: nil)

    XCTAssertEqual(phrase, "Got it")
  }

  func test_transitionPhrase_otherTransitions_returnNil() {
    // Only partial→full produces a transition phrase; everything else is nil.
    let cases: [(MatchStatus, MatchStatus)] = [
      (.unknown, .partial),
      (.unknown, .full),
      (.full, .partial),
      (.partial, .lost),
    ]
    for (from, to) in cases {
      XCTAssertNil(
        MatchStatusSpeech.transitionPhrase(from: from, to: to),
        "Expected nil for \(from) → \(to)")
    }
  }
}
