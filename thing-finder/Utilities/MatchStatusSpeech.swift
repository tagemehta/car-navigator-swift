//  MatchStatusSpeech.swift
//  thing-finder
//
//  Maps MatchStatus values to short, class-agnostic speech messages.
//
//  Ownership boundary
//  ──────────────────
//  • .waiting  — silent (PreMatchFeedbackController owns waiting feedback via earcon)
//  • .rejected — silent (PreMatchFeedbackController owns rejection announcements)
//  • .unknown  — silent (no retry messages; retryPhrase always returns nil)
//  • .partial  — "Possible match: [desc]" / "Possible match"
//  • .full     — "Found matching plate [plate]" / "Found [desc]" / "Found match"
//  • .lost     — direction hint if heading changed by more than 60°

import Foundation

func compareAngles(_ then: Double, _ now: Double) -> Double {
  var diff = now - then
  if diff > 180.0 { diff = diff - 360 }
  if diff < -180.0 { diff = diff + 360 }
  return diff  // if diff>0 then is to the right of now, diff<0 left
}

enum MatchStatusSpeech {
  static func phrase(
    for status: MatchStatus, recognisedText: String? = nil, detectedDescription: String? = nil,
    rejectReason: RejectReason? = nil, normalizedXPosition: CGFloat? = nil,
    settings: Settings? = nil, lastDirection: Double = -1,
    currentHeading: Double = -1
  ) -> String? {
    switch status {
    case .waiting:
      // Silent — the evaluation earcon already signals activity.
      return nil
    case .partial:
      if let desc = detectedDescription {
        return String(
          format: NSLocalizedString(
            "Possible match: %@",
            comment: "Speech: partial match with vehicle description"),
          desc)
      }
      return String(
        localized: "Possible match", comment: "Speech: partial match, no description available")
    case .full:
      if let plate = recognisedText {
        return String(
          format: NSLocalizedString(
            "Found matching plate %@",
            comment: "Speech: license plate matched"),
          plate)
      }
      if let desc = detectedDescription {
        return String(
          format: NSLocalizedString(
            "Found %@",
            comment: "Speech: vehicle description matched"),
          desc)
      }
      return String(localized: "Found match", comment: "Speech: generic match found")
    case .rejected:
      // Silent — PreMatchFeedbackController announces "Not yours — [desc]".
      return nil
    case .unknown:
      return nil
    case .lost:
      // Only announce compass direction if angle change is significant (>60°).
      // Too small = frequent interruptions as user naturally moves.
      // Too large = user never gets helpful directional info.
      // 60° represents a meaningful change worth announcing.
      let angle = round(compareAngles(lastDirection, currentHeading))
      if abs(angle) > 60.0 {
        if angle > 0 {
          let degrees = Int((abs(angle) / 30).rounded() * 30)
          return String(
            format: NSLocalizedString(
              "car was last seen %d degrees to the right",
              comment: "Speech: lost car direction right"),
            degrees)
        }
        if angle < 0 {
          let degrees = Int((abs(angle) / 30).rounded() * 30)
          return String(
            format: NSLocalizedString(
              "car was last seen %d degrees to the left",
              comment: "Speech: lost car direction left"),
            degrees)
        }
      }
      return nil
    }
  }

  /// Returns nil for all reasons — retry messages are no longer announced.
  /// Kept to avoid breaking call sites; can be removed in a future cleanup.
  static func retryPhrase(for reason: RejectReason) -> String? {
    return nil
  }
}
