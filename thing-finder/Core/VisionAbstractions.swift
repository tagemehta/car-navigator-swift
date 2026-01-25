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

// MARK: - Embedding Wrapper

/// Wrapper for feature-print embeddings. Can be created from `VNFeaturePrintObservation` or directly in tests.
/// Provides similarity comparison that works with both real Vision embeddings and test mocks.
public struct Embedding: Equatable {
  /// Unique identifier for this embedding
  public let id: UUID

  /// The underlying Vision feature-print, if created from one (production use)
  public let featurePrint: VNFeaturePrintObservation?

  /// Mock similarity values for testing: maps other Embedding.id -> similarity score
  private let mockSimilarities: [UUID: Float]

  /// Create from a Vision feature-print observation (production use)
  public init(from featurePrint: VNFeaturePrintObservation) {
    self.id = UUID()
    self.featurePrint = featurePrint
    self.mockSimilarities = [:]
  }

  /// Create directly for testing with optional mock similarity values
  /// - Parameters:
  ///   - id: Unique identifier (defaults to new UUID)
  ///   - mockSimilarities: Dictionary mapping other Embedding IDs to similarity scores (0-1)
  public init(id: UUID = UUID(), mockSimilarities: [UUID: Float] = [:]) {
    self.id = id
    self.featurePrint = nil
    self.mockSimilarities = mockSimilarities
  }

  /// Computes cosine similarity to another embedding.
  /// - Returns: Similarity score in 0...1 where 1 means identical
  /// - Throws: If similarity cannot be computed (e.g., incompatible embeddings)
  public func similarity(to other: Embedding) throws -> Float {
    // If both have real feature prints, use Vision's similarity
    if let selfFP = self.featurePrint, let otherFP = other.featurePrint {
      return try selfFP.cosineSimilarity(to: otherFP)
    }

    // Check mock similarities (either direction)
    if let sim = mockSimilarities[other.id] {
      return sim
    }
    if let sim = other.mockSimilarities[self.id] {
      return sim
    }

    // Same ID means identical
    if self.id == other.id {
      return 1.0
    }

    // Default: no similarity data available
    return 0.0
  }

  // Equatable based on ID
  public static func == (lhs: Embedding, rhs: Embedding) -> Bool {
    lhs.id == rhs.id
  }
}
