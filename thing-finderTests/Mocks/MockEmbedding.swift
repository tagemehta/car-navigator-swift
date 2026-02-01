//  MockEmbedding.swift
//  thing-finderTests
//
//  Mock embedding for testing. Provides configurable similarity values.

import Foundation

@testable import thing_finder

/// Mock embedding for testing that conforms to EmbeddingProtocol.
/// Allows configuring similarity values between embeddings.
public struct MockEmbedding: EmbeddingProtocol {
  public let id: UUID

  /// Maps other MockEmbedding IDs to similarity scores (0-1).
  private let similarities: [UUID: Float]

  /// Creates a mock embedding with optional pre-configured similarities.
  /// - Parameters:
  ///   - id: Unique identifier (defaults to new UUID)
  ///   - similarities: Dictionary mapping other embedding IDs to similarity scores
  public init(id: UUID = UUID(), similarities: [UUID: Float] = [:]) {
    self.id = id
    self.similarities = similarities
  }

  public func similarity(to other: any EmbeddingProtocol) throws -> Float {
    guard let otherMock = other as? MockEmbedding else {
      return 0.0
    }

    // Same ID = identical
    if id == otherMock.id {
      return 1.0
    }

    // Check configured similarities (either direction)
    if let sim = similarities[otherMock.id] {
      return sim
    }
    if let sim = otherMock.similarities[id] {
      return sim
    }

    // Default: no similarity
    return 0.0
  }
}
