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
public struct Candidate: Identifiable {
  // MARK: Core identity
  public let id: CandidateID

  // MARK: Tracking
  /// Tracking request responsible for updating `lastBoundingBox` frame-to-frame.
  /// Uses `TrackingRequest` wrapper struct for testability.
  public var trackingRequest: TrackingRequest

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
  /// same crop sent to the verifier. Uses protocol type for testability.
  public var embedding: (any EmbeddingProtocol)?

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
    case front, rear, left, right, side, unknown

    /// True for lateral views (left or right side of the vehicle).
    public var isSide: Bool { self == .left || self == .right || self == .side }
  }
  /// Most recent view angle reported by the verifier.
  public var view: VehicleView = .unknown
  /// Confidence score (0–1) of the current `view`.
  public var viewScore: Double = 0.0
  /// Timestamp when an MMR (fast-path) verification was last performed for this candidate.
  public var lastMMRTime: Date = .distantPast

  // MARK: Lifetime bookkeeping
  public var createdAt: Date = Date()
  public var lastUpdated: Date = Date()

  /// Consecutive frames where this candidate had **no** supporting detection.
  public var missCount: Int = 0

  // MARK: Init
  public init(
    id: CandidateID = UUID(),
    trackingRequest: TrackingRequest,
    boundingBox: CGRect,
    embedding: (any EmbeddingProtocol)? = nil
  ) {
    self.id = id
    self.trackingRequest = trackingRequest
    self.lastBoundingBox = boundingBox
    self.embedding = embedding
  }
}

// MARK: - Equatable

extension Candidate: Equatable {
  public static func == (lhs: Candidate, rhs: Candidate) -> Bool {
    lhs.id == rhs.id
      && lhs.trackingRequest == rhs.trackingRequest
      && lhs.lastBoundingBox == rhs.lastBoundingBox
      && lhs.matchStatus == rhs.matchStatus
      && lhs.missCount == rhs.missCount
      && lhs.verificationTracker == rhs.verificationTracker
      && lhs.view == rhs.view
      && lhs.viewScore == rhs.viewScore
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
  case noVehicleDetected = "no_vehicle_detected"
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
    case .unclearImage, .lowConfidence, .insufficientInfo, .apiError, .noVehicleDetected, .ambiguous,
      .licensePlateNotVisible:
      return true
    default:
      return false
    }
  }

  /// User-friendly description for announcements
  public var userFriendlyDescription: String {
    switch self {
    case .unclearImage:
      return String(
        localized: "Picture too blurry", comment: "Reject reason: image quality too low")
    case .lowConfidence:
      return String(
        localized: "Not confident enough", comment: "Reject reason: low detection confidence")
    case .insufficientInfo:
      return String(
        localized: "Need a better view", comment: "Reject reason: insufficient information")
    case .apiError: return String(localized: "Detection error", comment: "Reject reason: API error")
    case .noVehicleDetected:
      return String(
        localized: "No vehicle in frame", comment: "Reject reason: TrafficEye found no vehicle in crop")
    case .ambiguous:
      return String(localized: "Ambiguous result", comment: "Reject reason: ambiguous detection")
    case .licensePlateNotVisible:
      return String(
        localized: "License plate not visible", comment: "Reject reason: plate not visible")
    case .wrongModelOrColor:
      return String(localized: "Wrong make or model", comment: "Reject reason: wrong vehicle")
    case .licensePlateMismatch:
      return String(
        localized: "License plate doesn't match", comment: "Reject reason: plate mismatch")
    case .wrongObjectClass:
      return String(localized: "Not a vehicle", comment: "Reject reason: wrong object class")
    case .success: return ""
    }
  }
}
