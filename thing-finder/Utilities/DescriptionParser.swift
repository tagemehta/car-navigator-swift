//  DescriptionParser.swift
//  thing-finder
//
//  Utility to extract a license plate-like token from the user's natural
//  language description. Returns the cleaned plate string (e.g. "ABC123") and
//  the remainder of the description with the plate removed.
//
//  Regex assumes U.S-style alphanumerics 5-8 chars. Adjust as needed.
//
//  Created by Cascade AI on 2025-07-17.

import Foundation

enum DescriptionParser {
  /// Extracts a plausible license plate and returns (plate, remainder).
  /// Heuristic: token 5–8 chars, alphanumeric, contains at least 1 digit.
  static func extractPlate(from text: String) -> (plate: String?, remainder: String) {
    let tokens = text.split(separator: " ")
    var foundPlate: String?
    var tokenToRemove: Substring?

    for token in tokens {
      let cleaned = token.uppercased().replacingOccurrences(of: "-", with: "")
      guard cleaned.count >= 5, cleaned.count <= 8 else { continue }
      guard cleaned.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { continue }

      let hasDigit = cleaned.rangeOfCharacter(from: .decimalDigits) != nil
      let hasAlpha = cleaned.rangeOfCharacter(from: .letters) != nil
      guard hasDigit && hasAlpha else { continue }

      foundPlate = cleaned
      tokenToRemove = token
      break
    }

    // If we found a valid plate and its token, remove that token from the original text
    // and return the cleaned plate along with the remainder. Otherwise, return nil
    // for the plate and the original text unchanged.
    if let plate = foundPlate, let token = tokenToRemove {
      let remainder = tokens.filter { $0 != token }.joined(separator: " ")
      return (plate, remainder)
    }
    return (nil, text)
  }
}
