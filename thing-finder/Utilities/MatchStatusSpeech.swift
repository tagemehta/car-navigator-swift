//  MatchStatusSpeech.swift
//  thing-finder
//
//  Maps MatchStatus values to short, actionable speech messages.
//
//  Ownership boundary
//  ──────────────────
//  • .waiting      — silent (PreMatchFeedbackController owns waiting feedback via earcon)
//  • .rejected     — silent (PreMatchFeedbackController announces "Not yours — [desc]")
//  • .unknown      — silent
//  • .lostUnknown  — silent (unconfirmed; API still in-flight)
//  • .partial      — "Possible match — plate not visible"
//  • .full         — "Found it" / "Found it — plate [ABC 123]"
//  • .partial→.full — transitionPhrase: "Plate confirmed — [ABC 123]" / "Got it"
//  • .lostVerified — direction hint if heading changed by more than 60°
//  • .lostPartial  — direction hint (same as lostVerified; partial is a first-class nav signal)

import Foundation

func compareAngles(_ then: Double, _ now: Double) -> Double {
  var diff = now - then
  if diff > 180.0 { diff = diff - 360 }
  if diff < -180.0 { diff = diff + 360 }
  return diff  // positive → right, negative → left
}

enum MatchStatusSpeech {

  /// Phrase for a candidate in a given status.
  /// Returns nil for statuses that are handled elsewhere or should be silent.
  static func phrase(
    for status: MatchStatus,
    recognisedText: String? = nil,
    lastDirection: Double = -1,
    currentHeading: Double = -1
  ) -> String? {
    switch status {
    case .waiting:
      // Silent — the evaluation earcon already signals activity.
      return nil
    case .partial:
      return String(
        localized: "Possible match \u{2014} plate not visible",
        comment: "Speech: partial match found, plate not yet confirmed")
    case .full:
      if let plate = recognisedText {
        return String(
          format: NSLocalizedString(
            "Found it \u{2014} plate %@",
            comment: "Speech: vehicle found, license plate confirmed"),
          plate)
      }
      return String(localized: "Found it", comment: "Speech: vehicle found, no plate available")
    case .rejected:
      // Silent — PreMatchFeedbackController announces "Not yours — [desc]".
      return nil
    case .unknown:
      return nil
    case .lostUnknown:
      // Silent — candidate is unconfirmed; the API response hasn't landed yet.
      return nil
    case .lostVerified, .lostPartial:
      // Both are confirmed navigation signals. Announce compass direction once on transition.
      // Only fires if angle change is significant (>60°) to avoid noise on minor drifts.
      let angle = round(compareAngles(lastDirection, currentHeading))
      if angle > 60.0 {
        let degrees = Int((angle / 30).rounded() * 30)
        return String(
          format: NSLocalizedString(
            "car was last seen %d degrees to the right",
            comment: "Speech: lost car direction right"),
          degrees)
      }
      if angle < -60.0 {
        let degrees = Int((abs(angle) / 30).rounded() * 30)
        return String(
          format: NSLocalizedString(
            "car was last seen %d degrees to the left",
            comment: "Speech: lost car direction left"),
          degrees)
      }
      return nil
    }
  }

  /// Phrase for status upgrades, e.g. partial → full ("plate confirmed").
  /// Avoids repeating the initial-match phrase a second time.
  /// Returns nil if the transition does not warrant a distinct phrase.
  static func transitionPhrase(
    from oldStatus: MatchStatus,
    to newStatus: MatchStatus,
    recognisedText: String? = nil
  ) -> String? {
    switch (oldStatus, newStatus) {
    case (.partial, .full):
      if let plate = recognisedText {
        return String(
          format: NSLocalizedString(
            "Plate confirmed \u{2014} %@",
            comment: "Speech: partial match upgraded to full, plate now confirmed"),
          plate)
      }
      return String(
        localized: "Got it", comment: "Speech: partial match upgraded to full, no plate")
    default:
      return nil
    }
  }

  /// Returns nil for all reasons — retry messages are no longer announced.
  /// Retained to avoid breaking call sites; can be removed in a future cleanup.
  static func retryPhrase(for reason: RejectReason) -> String? {
    return nil
  }
}
