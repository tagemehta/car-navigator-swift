//  String+Levenshtein.swift
//  thing-finder
//
//  Adds a simple Levenshtein (edit-distance) computation to String.
//  Suitable for short license-plate sized strings (≤ 10 chars).
//
//  Created by Cascade AI on 2025-07-27.

import Foundation

extension String {
  /// Computes the Levenshtein edit distance to another string using
  /// a dynamic-programming algorithm. Runs in O(m·n) time and O(min(m,n)) space.
  ///
  /// - Parameter other: The string to compare with.
  /// - Returns: The number of single-character insertions, deletions or substitutions
  ///   required to transform `self` into `other`.
  func levenshteinDistance(to other: String) -> Int {
    // Early-exit for trivial cases
    if self == other { return 0 }
    if self.isEmpty { return other.count }
    if other.isEmpty { return self.count }

    let s = Array(self)
    let t = Array(other)
    let m = s.count
    let n = t.count

    // Use two rows to save memory
    var prev = Array(0...n) // 0-to-n
    var curr = Array(repeating: 0, count: n + 1)

    for i in 1...m {
      curr[0] = i
      for j in 1...n {
        let cost = s[i - 1] == t[j - 1] ? 0 : 1
        curr[j] = Swift.min(
          prev[j] + 1,          // deletion
          curr[j - 1] + 1,      // insertion
          prev[j - 1] + cost    // substitution
        )
      }
      swap(&prev, &curr)
    }
    return prev[n]
  }
}
