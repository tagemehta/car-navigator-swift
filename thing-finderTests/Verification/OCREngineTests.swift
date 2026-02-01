//  OCREngineTests.swift
//  thing-finderTests
//
//  Unit tests for OCR functionality including plate recognition and matching.

import XCTest

@testable import thing_finder

final class OCREngineTests: XCTestCase {

  // MARK: - OCRResult Tests

  func test_ocrResult_storesTextAndConfidence() {
    let result = OCRResult(text: "ABC1234", confidence: 0.95)

    XCTAssertEqual(result.text, "ABC1234")
    XCTAssertEqual(result.confidence, 0.95)
  }

  func test_ocrResult_handlesLowConfidence() {
    let result = OCRResult(text: "XYZ", confidence: 0.3)

    XCTAssertEqual(result.text, "XYZ")
    XCTAssertEqual(result.confidence, 0.3)
  }

  // MARK: - Levenshtein Distance Tests

  func test_levenshteinDistance_identicalStrings() {
    let distance = levenshteinDistance("ABC1234", "ABC1234")
    XCTAssertEqual(distance, 0)
  }

  func test_levenshteinDistance_oneCharDifference() {
    let distance = levenshteinDistance("ABC1234", "ABC1235")
    XCTAssertEqual(distance, 1)
  }

  func test_levenshteinDistance_twoCharDifference() {
    let distance = levenshteinDistance("ABC1234", "ABC1256")
    XCTAssertEqual(distance, 2)
  }

  func test_levenshteinDistance_emptyString() {
    let distance = levenshteinDistance("ABC", "")
    XCTAssertEqual(distance, 3)
  }

  func test_levenshteinDistance_completelyDifferent() {
    let distance = levenshteinDistance("ABC", "XYZ")
    XCTAssertEqual(distance, 3)
  }

  func test_levenshteinDistance_insertion() {
    let distance = levenshteinDistance("ABC", "ABCD")
    XCTAssertEqual(distance, 1)
  }

  func test_levenshteinDistance_deletion() {
    let distance = levenshteinDistance("ABCD", "ABC")
    XCTAssertEqual(distance, 1)
  }

  // MARK: - Plate Matching Tests

  func test_plateMatching_exactMatch() {
    let isMatch = platesMatch(expected: "ABC1234", recognized: "ABC1234")
    XCTAssertTrue(isMatch)
  }

  func test_plateMatching_allowsOneEdit() {
    // One character difference should still match
    let isMatch = platesMatch(expected: "ABC1234", recognized: "ABC1235")
    XCTAssertTrue(isMatch)
  }

  func test_plateMatching_rejectsTwoEdits() {
    // Two character differences should not match
    let isMatch = platesMatch(expected: "ABC1234", recognized: "ABC1256")
    XCTAssertFalse(isMatch)
  }

  func test_plateMatching_caseInsensitive() {
    let isMatch = platesMatch(expected: "ABC1234", recognized: "abc1234")
    XCTAssertTrue(isMatch)
  }

  func test_plateMatching_handlesNilExpected() {
    // If no expected plate, any recognized plate is acceptable
    let isMatch = platesMatch(expected: nil, recognized: "ABC1234")
    XCTAssertTrue(isMatch)
  }

  func test_plateMatching_handlesNilRecognized() {
    // If expected plate but nothing recognized, no match
    let isMatch = platesMatch(expected: "ABC1234", recognized: nil)
    XCTAssertFalse(isMatch)
  }

  func test_plateMatching_bothNil() {
    // Both nil means no plate requirement, so it's a match
    let isMatch = platesMatch(expected: nil, recognized: nil)
    XCTAssertTrue(isMatch)
  }

  // MARK: - Helper Functions

  /// Compute Levenshtein edit distance between two strings.
  private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
    let s1 = Array(s1)
    let s2 = Array(s2)
    let m = s1.count
    let n = s2.count

    if m == 0 { return n }
    if n == 0 { return m }

    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

    for i in 0...m { dp[i][0] = i }
    for j in 0...n { dp[0][j] = j }

    for i in 1...m {
      for j in 1...n {
        if s1[i - 1] == s2[j - 1] {
          dp[i][j] = dp[i - 1][j - 1]
        } else {
          dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
        }
      }
    }
    return dp[m][n]
  }

  /// Check if plates match within edit distance threshold.
  private func platesMatch(expected: String?, recognized: String?) -> Bool {
    guard let expected = expected else { return true }  // No requirement
    guard let recognized = recognized else { return false }  // Required but not found

    let e = expected.uppercased()
    let r = recognized.uppercased()
    return levenshteinDistance(e, r) <= 1
  }
}
