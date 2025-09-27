//  VerificationConfig.swift
//  thing-finder
//
//  Defines configurable parameters controlling the secondary license-plate OCR
//  verification flow.
//
//  Created by Cascade AI on 2025-07-17.

import Foundation

public struct VerificationConfig {
  /// The exact license plate we expect (uppercase, no spaces). Optional.
  public var expectedPlate: String?

  /// Validation regex for recognised text. Defaults to US-style 5–8 alphanumerics.
  public var regex: NSRegularExpression

  /// Minimum confidence from Vision OCR [0,1].
  public var ocrConfidenceMin: Double

  /// Maximum times we will attempt OCR on a candidate before rejecting.
  public var maxOCRRetries: Int

  /// Maximum Levenshtein edit distance considered a MATCH (full).
  public var maxEditsForMatch: Int
  /// Maximum edit distance that still allows us to CONTINUE (partial). Anything higher is rejected.
  public var maxEditsForContinue: Int

  /// Whether we should run OCR for this verification cycle.
  public var shouldRunOCR: Bool

  /// Maximum frequency (seconds) to call MMR for the *same* candidate.
  public var perCandidateMMRInterval: TimeInterval

  /// Whether verifier service should use the combined TrafficEye→LLM fallback strategy.
  public var useCombinedVerifier: Bool

  public init(
    expectedPlate: String?,
    regex: NSRegularExpression = try! NSRegularExpression(
      pattern: "^[A-Z0-9]{5,8}$", options: .caseInsensitive),
    ocrConfidenceMin: Double = 0.2,  // What are the odds you get an almost exact match on a license plate w/ the same make model at the same time in the same place
    maxOCRRetries: Int = 30,
    shouldRunOCR: Bool = false,
    maxEditsForMatch: Int = 1,  // an edit is a change in a single character of the ocr text
    maxEditsForContinue: Int = 2,  // an edit is a change in a single character of the ocr text
    useCombinedVerifier: Bool = true,
    perCandidateMMRInterval: TimeInterval = 0.8
  ) {
    self.expectedPlate = expectedPlate?.uppercased()
    self.regex = regex
    self.ocrConfidenceMin = ocrConfidenceMin
    self.maxOCRRetries = maxOCRRetries
    self.shouldRunOCR = shouldRunOCR
    self.maxEditsForMatch = maxEditsForMatch
    self.maxEditsForContinue = maxEditsForContinue
    self.useCombinedVerifier = useCombinedVerifier
    self.perCandidateMMRInterval = perCandidateMMRInterval
  }
}
