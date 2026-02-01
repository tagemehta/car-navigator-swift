//  MockSpeechOutput.swift
//  thing-finderTests
//
//  Mock implementation of SpeechOutput for testing NavAnnouncer and DirectionSpeechController.

import Foundation

@testable import thing_finder

final class MockSpeechOutput: SpeechOutput {
  /// All phrases spoken, in order.
  private(set) var spokenPhrases: [String] = []

  /// Timestamps of each spoken phrase.
  private(set) var speakTimestamps: [Date] = []

  /// Number of times speak() was called.
  var speakCallCount: Int { spokenPhrases.count }

  /// Last phrase spoken, if any.
  var lastPhrase: String? { spokenPhrases.last }

  func speak(_ text: String) {
    spokenPhrases.append(text)
    speakTimestamps.append(Date())
  }

  /// Reset all recorded state.
  func reset() {
    spokenPhrases.removeAll()
    speakTimestamps.removeAll()
  }

  /// Check if a specific phrase was spoken.
  func didSpeak(_ phrase: String) -> Bool {
    spokenPhrases.contains(phrase)
  }

  /// Check if any phrase containing the substring was spoken.
  func didSpeakContaining(_ substring: String) -> Bool {
    spokenPhrases.contains { $0.contains(substring) }
  }
}
