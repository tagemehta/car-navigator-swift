//  MatchStatusSpeechTests.swift
//  thing-finderTests
//
//  Unit tests for MatchStatusSpeech phrase generation.

import XCTest

@testable import thing_finder

final class MatchStatusSpeechTests: XCTestCase {

  // MARK: - Waiting Status
  // Waiting is now silent — feedback is handled by the earcon.

  func test_phrase_waiting_returnsNil() {
    let phrase = MatchStatusSpeech.phrase(for: .waiting)

    XCTAssertNil(phrase)
  }

  // MARK: - Full Match Status

  func test_phrase_fullWithPlate_returnsFoundPlateMessage() {
    let phrase = MatchStatusSpeech.phrase(
      for: .full,
      recognisedText: "ABC1234"
    )

    XCTAssertEqual(phrase, "Found matching plate ABC1234")
  }

  func test_phrase_fullWithDescription_returnsFoundDescriptionMessage() {
    let phrase = MatchStatusSpeech.phrase(
      for: .full,
      recognisedText: nil,
      detectedDescription: "blue Honda Civic"
    )

    XCTAssertEqual(phrase, "Found blue Honda Civic")
  }

  func test_phrase_fullWithBoth_prefersPlate() {
    let phrase = MatchStatusSpeech.phrase(
      for: .full,
      recognisedText: "XYZ789",
      detectedDescription: "red Toyota"
    )

    XCTAssertEqual(phrase, "Found matching plate XYZ789")
  }

  func test_phrase_fullWithNeither_returnsGenericMatch() {
    let phrase = MatchStatusSpeech.phrase(for: .full)

    XCTAssertEqual(phrase, "Found match")
  }

  // MARK: - Partial Match Status
  // Partial now uses "Possible match" phrasing — no "Warning:" prefix.

  func test_phrase_partialWithDescription_returnsPossibleMatch() {
    let phrase = MatchStatusSpeech.phrase(
      for: .partial,
      detectedDescription: "blue Honda"
    )

    XCTAssertEqual(phrase, "Possible match: blue Honda")
  }

  func test_phrase_partialWithoutDescription_returnsPossibleMatch() {
    let phrase = MatchStatusSpeech.phrase(for: .partial)

    XCTAssertEqual(phrase, "Possible match")
  }

  // MARK: - Rejected Status
  // Rejected is now silent here — PreMatchFeedbackController owns rejection announcements.

  func test_phrase_rejectedWithDescription_returnsNil() {
    let phrase = MatchStatusSpeech.phrase(
      for: .rejected,
      detectedDescription: "red Toyota",
      rejectReason: .wrongModelOrColor
    )

    XCTAssertNil(phrase)
  }

  func test_phrase_rejectedWithoutInfo_returnsNil() {
    let phrase = MatchStatusSpeech.phrase(for: .rejected)

    XCTAssertNil(phrase)
  }

  // MARK: - Unknown Status

  func test_phrase_unknown_returnsNil() {
    let phrase = MatchStatusSpeech.phrase(for: .unknown)

    XCTAssertNil(phrase)
  }

  // MARK: - Lost Status

  func test_phrase_lost_withSmallAngleChange_returnsNil() {
    // Small angle change (< 60°) should not announce
    let phrase = MatchStatusSpeech.phrase(
      for: .lost,
      lastDirection: 0.0,
      currentHeading: 30.0  // Only 30° change — below 60° threshold
    )

    XCTAssertNil(phrase)
  }

  func test_phrase_lost_withLargeAngleChange_returnsDirection() {
    // Large angle change (> 60°) should announce direction
    let phrase = MatchStatusSpeech.phrase(
      for: .lost,
      lastDirection: 0.0,
      currentHeading: 90.0  // 90° change to the right
    )

    XCTAssertNotNil(phrase)
    XCTAssertTrue(phrase!.contains("degrees to the right"))
  }

  func test_phrase_lost_withLargeLeftAngle_returnsLeft() {
    let phrase = MatchStatusSpeech.phrase(
      for: .lost,
      lastDirection: 90.0,
      currentHeading: 0.0  // 90° change to the left
    )

    XCTAssertNotNil(phrase)
    XCTAssertTrue(phrase!.contains("degrees to the left"))
  }

  // MARK: - Retry Phrases
  // All retry phrases now return nil — no retry speech announced.

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
}
