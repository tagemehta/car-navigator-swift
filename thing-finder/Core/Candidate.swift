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

  // MARK: Verification attempt counters
  /// Counts of verification attempts per verifier – durable across app restarts.
  public struct VerificationTracker: Codable, Equatable {
    public var trafficAttempts: Int = 0  // failed TrafficEye attempts
    public var llmAttempts: Int = 0  // failed LLM attempts
  }
  public var verificationTracker = VerificationTracker()

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
  public var rejectReason: RejectReason?
  /// Number of OCR attempts executed so far (licence-plate verification).
  public var ocrAttempts: Int = 0
  /// Last recognised text (if any) for debugging / speech.
  public var ocrText: String?

  public var degrees: Double = -1.0

  /// Convenience – true when verifier has fully approved this candidate.
  public var isMatched: Bool { matchStatus == .full }

  // MARK: View angle tracking
  public enum VehicleView: String, Codable {
    case front, rear, side, unknown
  }
  /// Best view observed for this candidate so far.
  public var view: VehicleView = .unknown
  /// Confidence score (0–1) of the current `view`.
  public var viewScore: Double = 0.0
  /// Timestamp when an MMR (fast-path) verification was last performed for this candidate.
  public var lastMMRTime: Date = .distantPast
  /// If side/unknown view was last seen, we wait until this time before consulting LLM.

  /// Update the stored view only if it is an improvement.
  public mutating func updateView(_ newView: VehicleView, score: Double) {
    // Prefer front/rear over side/unknown, else prefer higher score.
    func rank(_ v: VehicleView) -> Int {
      switch v {
      case .front, .rear: return 2
      case .side: return 1
      case .unknown: return 0
      }
    }
    let currentRank = rank(view)
    let newRank = rank(newView)
    if newRank > currentRank || (newRank == currentRank && score > viewScore) {
      view = newView
      viewScore = score
    }
  }

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

/// Verification state for a candidate.
///
/// Flow: `unknown` → `waiting` → `partial`/`full`/`rejected`
///       `full` → `lost` (when tracking fails)
public enum MatchStatus: String, Codable {
  /// Detector output, API not called yet
  case unknown
  /// API verification in-flight
  case waiting
  /// API matched vehicle, but license plate not yet confirmed (OCR pending)
  case partial
  /// Fully verified: vehicle + plate confirmed (or plate not required)
  case full
  /// Hard rejection: wrong vehicle, wrong plate, or retry exhausted
  case rejected
  /// Was `.full` but tracking lost the bounding box. Candidate stays `.full` while
  /// actively tracked; only becomes `.lost` when missCount exceeds threshold.
  case lost
}

/// Specific reason for rejection or retry of a candidate.
public enum RejectReason: String, Codable {
  // Retryable reasons (will set candidate to .unknown)
  case unclearImage = "unclear_image"
  case lowConfidence = "low_confidence"
  case insufficientInfo = "insufficient_info"
  case apiError = "api_error"
  case ambiguous = "ambiguous"
  case licensePlateNotVisible = "license_plate_not_visible"

  // Hard reject reasons (will set candidate to .rejected)
  case wrongModelOrColor = "wrong_model_or_color"
  case licensePlateMismatch = "license_plate_mismatch"
  case wrongObjectClass = "wrong_object_class"

  // Success case
  case success = "success"

  /// Whether this reason should trigger a retry rather than a hard rejection
  public var isRetryable: Bool {
    switch self {
    case .unclearImage, .lowConfidence, .insufficientInfo, .apiError, .ambiguous,
      .licensePlateNotVisible:
      return true
    default:
      return false
    }
  }

  /// User-friendly description for announcements
  public var userFriendlyDescription: String {
    switch self {
    case .unclearImage: return "Picture too blurry"
    case .lowConfidence: return "Not confident enough"
    case .insufficientInfo: return "Need a better view"
    case .apiError: return "Detection error"
    case .ambiguous: return "Ambiguous result"
    case .licensePlateNotVisible: return "License plate not visible"
    case .wrongModelOrColor: return "Wrong make or model"
    case .licensePlateMismatch: return "License plate doesn't match"
    case .wrongObjectClass: return "Not a vehicle"
    case .success: return ""
    }
  }
}
