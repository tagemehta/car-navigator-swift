//  DescriptionParserTests.swift
//  thing-finderTests
//
//  Unit tests for DescriptionParser license plate extraction.

import XCTest

@testable import thing_finder

final class DescriptionParserTests: XCTestCase {

  // MARK: - Valid Plate Extraction

  func test_extractPlate_findsValidPlate() {
    let result = DescriptionParser.extractPlate(from: "Blue Honda ABC1234")

    XCTAssertEqual(result.plate, "ABC1234")
  }

  func test_extractPlate_handlesLowercase() {
    let result = DescriptionParser.extractPlate(from: "blue honda abc1234")

    XCTAssertEqual(result.plate, "ABC1234")
  }

  func test_extractPlate_handlesDashes() {
    let result = DescriptionParser.extractPlate(from: "Blue Honda ABC-1234")

    XCTAssertEqual(result.plate, "ABC1234")
    XCTAssertEqual(result.remainder, "Blue Honda")
  }

  func test_extractPlate_findsPlateAtStart() {
    let result = DescriptionParser.extractPlate(from: "ABC1234 Blue Honda")

    XCTAssertEqual(result.plate, "ABC1234")
  }

  func test_extractPlate_findsPlateInMiddle() {
    let result = DescriptionParser.extractPlate(from: "Blue ABC1234 Honda Civic")

    XCTAssertEqual(result.plate, "ABC1234")
  }

  // MARK: - Plate Requirements

  func test_extractPlate_requiresDigitAndLetter() {
    // All digits - should fail
    let digitsOnly = DescriptionParser.extractPlate(from: "Blue Honda 12345678")
    XCTAssertNil(digitsOnly.plate)

    // All letters - should fail
    let lettersOnly = DescriptionParser.extractPlate(from: "Blue Honda ABCDEFGH")
    XCTAssertNil(lettersOnly.plate)
  }

  func test_extractPlate_requiresMinLength() {
    // Too short (4 chars)
    let tooShort = DescriptionParser.extractPlate(from: "Blue Honda AB12")
    XCTAssertNil(tooShort.plate)
  }

  func test_extractPlate_requiresMaxLength() {
    // Too long (9 chars)
    let tooLong = DescriptionParser.extractPlate(from: "Blue Honda ABC123456")
    XCTAssertNil(tooLong.plate)
  }

  func test_extractPlate_rejectsSpecialCharacters() {
    let result = DescriptionParser.extractPlate(from: "Blue Honda ABC@123")
    XCTAssertNil(result.plate)
  }

  // MARK: - Remainder Handling

  func test_extractPlate_removesFromRemainder() {
    let result = DescriptionParser.extractPlate(from: "Blue Honda ABC1234 Civic")

    XCTAssertEqual(result.plate, "ABC1234")
    XCTAssertEqual(result.remainder, "Blue Honda Civic")
  }

  func test_extractPlate_trimsRemainderWhitespace() {
    let result = DescriptionParser.extractPlate(from: "ABC1234 Blue Honda")

    XCTAssertEqual(result.remainder, "Blue Honda")
    XCTAssertFalse(result.remainder.hasPrefix(" "))
    XCTAssertFalse(result.remainder.hasSuffix(" "))
  }

  // MARK: - No Plate Cases

  func test_extractPlate_handlesNoPlate() {
    let result = DescriptionParser.extractPlate(from: "Blue Honda Civic")

    XCTAssertNil(result.plate)
    XCTAssertEqual(result.remainder, "Blue Honda Civic")
  }

  func test_extractPlate_handlesEmptyString() {
    let result = DescriptionParser.extractPlate(from: "")

    XCTAssertNil(result.plate)
    XCTAssertEqual(result.remainder, "")
  }

  // MARK: - Edge Cases

  func test_extractPlate_findsFirstValidPlate() {
    // If multiple valid plates, should find first one
    let result = DescriptionParser.extractPlate(from: "ABC1234 XYZ5678")

    XCTAssertEqual(result.plate, "ABC1234")
  }

  func test_extractPlate_handlesMinValidLength() {
    // 5 chars is minimum
    let result = DescriptionParser.extractPlate(from: "Blue Honda AB123")

    XCTAssertEqual(result.plate, "AB123")
  }

  func test_extractPlate_handlesMaxValidLength() {
    // 8 chars is maximum
    let result = DescriptionParser.extractPlate(from: "Blue Honda ABCD1234")

    XCTAssertEqual(result.plate, "ABCD1234")
  }

  func test_extractPlate_caseInsensitiveRemoval() {
    // Original has lowercase, should still be removed
    let result = DescriptionParser.extractPlate(from: "Blue abc1234 Honda")

    XCTAssertEqual(result.plate, "ABC1234")
    XCTAssertEqual(result.remainder, "Blue Honda")
  }
}
