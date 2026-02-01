//  VisionAbstractions.swift
//  thing-finder
//
//  Wrapper types to abstract Vision framework types for improved testability.
//  Production code converts Vision types to these wrappers; tests create them directly.

import CoreGraphics
import Foundation
import Vision

// MARK: - Label Wrapper

/// Wrapper for classification labels. Can be created from `VNClassificationObservation` or directly in tests.
public struct DetectionLabel: Sendable {
  public let identifier: String
  public let confidence: Float

  public init(identifier: String, confidence: Float) {
    self.identifier = identifier
    self.confidence = confidence
  }

  public init(from observation: VNClassificationObservation) {
    self.identifier = observation.identifier
    self.confidence = observation.confidence
  }
}

// MARK: - Detection Wrapper

/// Wrapper for object detections. Can be created from `VNRecognizedObjectObservation` or directly in tests.
public struct Detection {
  public let boundingBox: CGRect
  public let labels: [DetectionLabel]
  public let confidence: Float
  public let uuid: UUID

  /// The underlying Vision observation, if this Detection was created from one.
  /// Used when we need to create a VNTrackObjectRequest.
  public let observation: VNRecognizedObjectObservation?

  /// Create from a Vision observation (production use)
  public init(from observation: VNRecognizedObjectObservation) {
    self.boundingBox = observation.boundingBox
    self.labels = observation.labels.map { DetectionLabel(from: $0) }
    self.confidence = observation.confidence
    self.uuid = observation.uuid
    self.observation = observation
  }

  /// Create directly (test use)
  public init(
    boundingBox: CGRect,
    labels: [DetectionLabel],
    confidence: Float = 1.0,
    uuid: UUID = UUID()
  ) {
    self.boundingBox = boundingBox
    self.labels = labels
    self.confidence = confidence
    self.uuid = uuid
    self.observation = nil
  }
}

// MARK: - Embedding Protocol

/// Protocol for embeddings that can compute similarity.
/// Allows production code to use real Vision embeddings while tests can inject mocks.
public protocol EmbeddingProtocol {
  func similarity(to other: any EmbeddingProtocol) throws -> Float
}

// MARK: - Embedding

/// Production embedding wrapper around Vision's VNFeaturePrintObservation.
public struct Embedding: EmbeddingProtocol, Equatable {
  /// Unique identifier for this embedding
  public let id: UUID

  /// The underlying Vision feature-print
  public let featurePrint: VNFeaturePrintObservation

  /// Create from a Vision feature-print observation
  public init(from featurePrint: VNFeaturePrintObservation) {
    self.id = UUID()
    self.featurePrint = featurePrint
  }

  /// Computes cosine similarity to another embedding using Vision.
  /// - Returns: Similarity score in 0...1 where 1 means identical
  /// - Throws: If similarity cannot be computed (e.g., incompatible embeddings)
  public func similarity(to other: any EmbeddingProtocol) throws -> Float {
    guard let otherEmb = other as? Embedding else {
      return 0.0
    }
    return try featurePrint.cosineSimilarity(to: otherEmb.featurePrint)
  }

  public static func == (lhs: Embedding, rhs: Embedding) -> Bool {
    lhs.id == rhs.id
  }
}
