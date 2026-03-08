//  VerificationConfig.swift
//  thing-finder
//
//  Defines configurable parameters controlling the secondary license-plate OCR
//  verification flow.
//
//  Created by Cascade AI on 2025-07-17.

import Foundation

// MARK: - Verifier Strategy

/// Defines which verifier(s) to use for vehicle verification.
public enum VerifierStrategy {
  /// Standard car search: TrafficEye (fast) → LLM (fallback) escalation loop.
  /// TrafficEye attempts first, escalates to LLM after failures, cycles back.
  case hybrid

  /// Always use advanced LLM verifier, skip TrafficEye entirely.
  /// Use for paratransit (wheelchair lifts, ramps) or custom features TrafficEye can't detect.
  case llmOnly

  /// Always use TrafficEye, never escalate to LLM.
  /// Use for simple MMR-only verification when LLM is unnecessary.
  case trafficEyeOnly
}

public struct VerificationConfig {
  /// The exact license plate we expect (uppercase, no spaces). Optional.
  public var expectedPlate: String?

  /// Validation regex for recognised text. Defaults to US-style 5–8 alphanumerics.
  public var regex: NSRegularExpression

  /// Minimum confidence from Vision OCR [0,1].
  public var ocrConfidenceMin: Double

  /// Maximum times we will attempt OCR on a candidate before rejecting.
  /// - Note: **Legacy value.** Originally set high (30) because OCR might miss by a single
  ///   character. Now that Levenshtein distance matching is implemented via `maxEditsForMatch`,
  ///   fuzzy matching handles minor OCR errors automatically. This limit could be reduced.
  public var maxOCRRetries: Int

  /// Maximum Levenshtein edit distance considered a MATCH (full).
  public var maxEditsForMatch: Int
  /// Maximum edit distance that still allows us to CONTINUE (partial). Anything higher is rejected.
  public var maxEditsForContinue: Int

  /// Whether we should run OCR for this verification cycle.
  public var shouldRunOCR: Bool

  /// Maximum frequency (seconds) to call MMR for the *same* candidate.
  public var perCandidateMMRInterval: TimeInterval

  /// Which verifier(s) to use for verification.
  public var strategy: VerifierStrategy

  public init(
    expectedPlate: String?,
    regex: NSRegularExpression = try! NSRegularExpression(
      pattern: "^[A-Z0-9]{5,8}$", options: .caseInsensitive),
    ocrConfidenceMin: Double = 0.2,  // What are the odds you get an almost exact match on a license plate w/ the same make model at the same time in the same place
    maxOCRRetries: Int = 30,
    shouldRunOCR: Bool = false,
    maxEditsForMatch: Int = 1,  // an edit is a change in a single character of the ocr text
    maxEditsForContinue: Int = 2,  // an edit is a change in a single character of the ocr text
    strategy: VerifierStrategy = .hybrid,
    perCandidateMMRInterval: TimeInterval = 0.8
  ) {
    self.expectedPlate = expectedPlate?.uppercased()
    self.regex = regex
    self.ocrConfidenceMin = ocrConfidenceMin
    self.maxOCRRetries = maxOCRRetries
    self.shouldRunOCR = shouldRunOCR
    self.maxEditsForMatch = maxEditsForMatch
    self.maxEditsForContinue = maxEditsForContinue
    self.strategy = strategy
    self.perCandidateMMRInterval = perCandidateMMRInterval
  }
}
