//  ImageVerifier.swift
//  thing-finder
//
//  Defines a minimal protocol abstracting over any component that can verify an
//  object crop (as base-64 image data) against the user’s natural-language
//  target description.  This allows `VerifierService` to depend on a protocol
//  instead of concrete, `final` `LLMVerifier`, making unit testing easier.
//
//  Created by Cascade AI on 2025-07-20.

import Combine
import Foundation
import UIKit

/// Lightweight outcome model shared between verifier implementations and tests.
public struct VerificationOutcome {
  public let isMatch: Bool
  public let description: String
  public let rejectReason: RejectReason?
  public let isPlateMatch: Bool
  public let vehicleView: Candidate.VehicleView?
  public let viewScore: Double?

  public init(
    isMatch: Bool,
    description: String,
    rejectReason: RejectReason?,
    isPlateMatch: Bool = false,
    vehicleView: Candidate.VehicleView? = nil,
    viewScore: Double? = nil
  ) {
    self.isMatch = isMatch
    self.description = description
    self.rejectReason = rejectReason
    self.isPlateMatch = isPlateMatch
    self.vehicleView = vehicleView
    self.viewScore = viewScore
  }
}

/// Protocol that any verification engine (LLM, on-device model, etc.) must
/// satisfy so the pipeline can request verifications agnostically.
public protocol ImageVerifier {
  /// CLASSES of objects we’re looking for (e.g. ["car", "bottle"…]).
  var targetClasses: [String] { get }
  /// Full natural-language description the user entered.
  var targetTextDescription: String { get }

  /// Returns a publisher that eventually emits a `VerificationOutcome`.
  func verify(image: UIImage, candidateId: UUID) -> AnyPublisher<VerificationOutcome, Error>

  /// Seconds since the last call to `verify` finished.
  func timeSinceLastVerification() -> TimeInterval
}
