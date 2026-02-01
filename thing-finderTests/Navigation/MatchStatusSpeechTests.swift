//  MatchStatusSpeechTests.swift
//  thing-finderTests
//
//  Unit tests for MatchStatusSpeech phrase generation.

import XCTest

@testable import thing_finder

final class MatchStatusSpeechTests: XCTestCase {

  // MARK: - Waiting Status

  func test_phrase_waiting_returnsWaitingMessage() {
    let phrase = MatchStatusSpeech.phrase(for: .waiting)

    XCTAssertEqual(phrase, "Waiting for verification")
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

  func test_phrase_partialWithDescription_includesWarning() {
    let phrase = MatchStatusSpeech.phrase(
      for: .partial,
      detectedDescription: "blue Honda"
    )

    XCTAssertEqual(phrase, "Found blue Honda. Warning: Plate not visible yet")
  }

  func test_phrase_partialWithoutDescription_returnsPlateNotVisible() {
    let phrase = MatchStatusSpeech.phrase(for: .partial)

    XCTAssertEqual(phrase, "Plate not visible yet")
  }

  // MARK: - Rejected Status

  func test_phrase_rejectedWithDescriptionAndReason_includesBoth() {
    let phrase = MatchStatusSpeech.phrase(
      for: .rejected,
      detectedDescription: "red Toyota",
      rejectReason: .wrongModelOrColor
    )

    XCTAssertNotNil(phrase)
    XCTAssertTrue(phrase!.contains("red Toyota"))
  }

  func test_phrase_rejectedWithoutInfo_returnsGenericFailure() {
    let phrase = MatchStatusSpeech.phrase(for: .rejected)

    XCTAssertEqual(phrase, "Verification failed")
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
      lastDirection: CompassHeading.shared.degrees  // Same as current
    )

    XCTAssertNil(phrase)
  }

  // MARK: - Retry Phrases

  func test_retryPhrase_unclearImage_returnsBlurryMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .unclearImage)

    XCTAssertEqual(phrase, "Picture too blurry, trying again")
  }

  func test_retryPhrase_insufficientInfo_returnsBetterViewMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .insufficientInfo)

    XCTAssertEqual(phrase, "Need a better view, retrying")
  }

  func test_retryPhrase_lowConfidence_returnsNotSureMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .lowConfidence)

    XCTAssertEqual(phrase, "Not sure yet, taking another shot")
  }

  func test_retryPhrase_apiError_returnsErrorMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .apiError)

    XCTAssertEqual(phrase, "Detection error, retrying")
  }

  func test_retryPhrase_licensePlateNotVisible_returnsPlateMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .licensePlateNotVisible)

    XCTAssertEqual(phrase, "Can't see the plate, retrying")
  }

  func test_retryPhrase_ambiguous_returnsUnclearMessage() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .ambiguous)

    XCTAssertEqual(phrase, "Results unclear, retrying")
  }

  func test_retryPhrase_hardReject_returnsNil() {
    // Hard rejects should not have retry phrases
    let phrase = MatchStatusSpeech.retryPhrase(for: .wrongModelOrColor)

    XCTAssertNil(phrase)
  }

  func test_retryPhrase_success_returnsNil() {
    let phrase = MatchStatusSpeech.retryPhrase(for: .success)

    XCTAssertNil(phrase)
  }
}
