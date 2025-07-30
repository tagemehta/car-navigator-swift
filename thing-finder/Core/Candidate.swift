//  Candidate.swift
//  thing-finder
//
//  Created by Cascade AI on 2025-07-13.
//
//  Value-type model representing an object candidate currently being tracked
//  in the per-frame detection pipeline.  The struct is intentionally free of
//  ARKit-specific concepts (e.g. anchors) so it works for both AVFoundation and
//  ARKit capture modes.
//
//  This file contains **no** business logic – only the data container.  All
//  mutation happens through `CandidateStore` helpers to keep thread-safety via
//  main-queue publishes.

import Foundation
import Vision

/// Convenience alias for the primary key used throughout the pipeline.
public typealias CandidateID = UUID

/// Vision + verification candidate tracked across frames.
public struct Candidate: Identifiable, Equatable {
  // MARK: Core identity
  public let id: CandidateID

  // MARK: Tracking
  /// Vision tracking request responsible for updating `lastBoundingBox` frame-to-frame.
  public var trackingRequest: VNTrackObjectRequest

  /// Last known axis-aligned bounding box in **image** coordinates (0-1).
  public var lastBoundingBox: CGRect

  // MARK: Verification & drift repair
  /// Feature-print embedding generated via `VNGenerateImageFeaturePrintRequest` on the
  /// same crop sent to the verifier.  Length is typically 128 floats.
  public var embedding: VNFeaturePrintObservation?

  /// Verification progress for this candidate.
  public var matchStatus: MatchStatus = .unknown
  /// Timestamp of the most recent *successful* LLM verification (partial or full).
  public var lastVerified: Date?
  
  /// Human-readable description returned by LLM, e.g. “blue Toyota Camry”.
  public var detectedDescription: String?
  /// Reason for rejection when matchStatus == .rejected.
  public var rejectReason: String?
  /// Number of OCR attempts executed so far (licence-plate verification).
  public var ocrAttempts: Int = 0
  /// Last recognised text (if any) for debugging / speech.
  public var ocrText: String?
  
  /// Convenience – true when verifier has fully approved this candidate.
  public var isMatched: Bool { matchStatus == .full }

  // MARK: Lifetime bookkeeping
  public var createdAt: Date = Date()
  public var lastUpdated: Date = Date()
  
  /// Consecutive frames where this candidate had **no** supporting detection.
  public var missCount: Int = 0

  // MARK: Init
  public init(
    id: CandidateID = UUID(),
    trackingRequest: VNTrackObjectRequest,
    boundingBox: CGRect,
    embedding: VNFeaturePrintObservation? = nil
  ) {
    self.id = id
    self.trackingRequest = trackingRequest
    self.lastBoundingBox = boundingBox
    self.embedding = embedding
  }
}

// MARK: - MatchStatus enum (copied from existing model if present)

/// LLM verification result for a candidate.
public enum MatchStatus: String, Codable {
  case unknown   // detector output, API not called yet
  case waiting   // API verification in-flight
  case partial   // API matched, plate not confirmed
  case full      // API + plate confirmed
  case rejected  // negative result (wrong plate / retry exhausted)
}
