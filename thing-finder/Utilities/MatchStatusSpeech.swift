//  MatchStatusSpeech.swift
//  thing-finder
//
//  Maps MatchStatus values to short, class-agnostic speech messages.
//
//  Created by Cascade AI on 2025-07-17.

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
      return String(
        localized: "Waiting for verification", comment: "Speech: verification in progress")
    case .partial:
      if let desc = detectedDescription {
        return String(
          format: NSLocalizedString(
            "Found %@. Warning: Plate not visible yet",
            comment: "Speech: vehicle found but plate not confirmed"),
          desc)
      }
      return String(localized: "Plate not visible yet", comment: "Speech: partial match, no plate")
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
      if let desc = detectedDescription, let reason = rejectReason {
        // Add directional information for wrong make/model
        if reason == .wrongModelOrColor, let normalizedX = normalizedXPosition,
          let settings = settings
        {
          let direction = settings.getDirection(normalizedX: normalizedX)
          return String(
            format: NSLocalizedString(
              "%@ – %@ %@",
              comment: "Speech: rejected with direction"),
            desc, reason.userFriendlyDescription, direction.localizedName)
        }
        return String(
          format: NSLocalizedString(
            "%@ – %@",
            comment: "Speech: rejected with reason"),
          desc, reason.userFriendlyDescription)
      }
      return String(
        localized: "Verification failed", comment: "Speech: generic verification failure")
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

  /// Get a phrase to announce when retrying due to a specific reason
  static func retryPhrase(for reason: RejectReason) -> String? {
    switch reason {
    case .unclearImage:
      return String(
        localized: "Picture too blurry, trying again", comment: "Speech: retry due to blurry image")
    case .insufficientInfo:
      return String(
        localized: "Need a better view, retrying", comment: "Speech: retry due to insufficient info"
      )
    case .lowConfidence:
      return String(
        localized: "Not sure yet, taking another shot",
        comment: "Speech: retry due to low confidence")
    case .noVehicleDetected:
      return String(
        localized: "Can't make out the vehicle, retrying",
        comment: "Speech: retry because TrafficEye found no vehicle in crop")
    case .apiError:
      return String(
        localized: "Detection error, retrying", comment: "Speech: retry due to API error")
    case .licensePlateNotVisible:
      return String(
        localized: "Can't see the plate, retrying",
        comment: "Speech: retry due to plate not visible")
    case .ambiguous:
      return String(
        localized: "Results unclear, retrying", comment: "Speech: retry due to ambiguous result")
    default: return nil  // no speech for hard rejects
    }
  }
}
