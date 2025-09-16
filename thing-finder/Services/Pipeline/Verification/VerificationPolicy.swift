//  VerificationPolicy.swift
//  thing-finder
//
//  Decides which verifier (TrafficEye vs LLM) should be used for a given
//  candidate based on durable attempt counters.
//
//  Created by Cascade AI.

import Foundation

public enum VerifierKind {
  case trafficEye
  case llm
}

public struct VerificationPolicy {
  /// After the initial TrafficEye call classifies the orientation, side-view frames
  /// escalate to the LLM immediately on the *next* failure (i.e. after 1 prior TE attempt).
  public static let minPrimaryRetries: Int = 1
  /// Hard cap – any candidate escalates to LLM after this many consecutive TrafficEye failures.
  public static let maxPrimaryRetries: Int = 3
  /// After this many consecutive LLM failures we fall back to TrafficEye again.
  public static let maxLLMRetries: Int = 3

  public static func nextKind(for candidate: Candidate) -> VerifierKind {
    // First: if LLM has already failed too many times, cycle back to TrafficEye
    if candidate.verificationTracker.llmAttempts >= maxLLMRetries {
      return .trafficEye
    }
    // Escalate to LLM when TrafficEye keeps failing (any view)
    if candidate.verificationTracker.trafficAttempts >= maxPrimaryRetries {
      return .llm
    }
    // Earlier fallback for side view after fewer failures
    if candidate.view == .side && candidate.verificationTracker.trafficAttempts >= minPrimaryRetries
    {
      return .llm
    }
    return .trafficEye
  }
}
