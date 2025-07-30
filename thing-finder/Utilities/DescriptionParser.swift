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
    var plateToken: Substring?
    for token in tokens {
      // Strip punctuation / dashes
      let cleaned = token.uppercased().replacingOccurrences(of: "-", with: "")
      // Check length and character set
      guard cleaned.count >= 5, cleaned.count <= 8 else { continue }
      guard cleaned.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { continue }
      // Must contain at least one digit and one letter
      let hasDigit = cleaned.rangeOfCharacter(from: .decimalDigits) != nil
      let hasAlpha = cleaned.rangeOfCharacter(from: .letters) != nil
      guard hasDigit && hasAlpha else { continue }
      plateToken = cleaned[...]
      break
    }
    if let plate = plateToken {
      // Remove first occurrence from original text (case-insensitive)
      if let range = text.range(of: plate, options: .caseInsensitive) {
        var remainder = text
        remainder.replaceSubrange(range, with: "")  // Replace plate with placeholder for llm
        return (String(plate), remainder.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      return (String(plate), text)
    }
    return (nil, text)
  }
}
