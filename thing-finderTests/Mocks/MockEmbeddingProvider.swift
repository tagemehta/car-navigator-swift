//  MockEmbeddingProvider.swift
//  thing-finderTests
//
//  Mock implementation of EmbeddingProvider for testing DriftRepairService.
//  Allows controlled embedding responses and similarity values.

import CoreGraphics
import ImageIO

@testable import thing_finder

/// Mock embedding provider that returns pre-configured MockEmbeddings for testing.
final class MockEmbeddingProvider: EmbeddingProvider {

  /// Maps detection bounding box to the embedding to return.
  /// Uses bounding box origin as key (rounded to avoid floating point issues).
  var embeddingsForBoundingBox: [String: MockEmbedding] = [:]

  /// Default embedding to return if no specific mapping exists.
  var defaultEmbedding: MockEmbedding?

  /// Tracks how many times computeEmbedding was called.
  private(set) var computeCallCount: Int = 0

  /// Records the bounding boxes passed to computeEmbedding.
  private(set) var computedBoundingBoxes: [CGRect] = []

  func computeEmbedding(
    from cgImage: CGImage,
    boundingBox: CGRect,
    orientation: CGImagePropertyOrientation
  ) -> (any EmbeddingProtocol)? {
    computeCallCount += 1
    computedBoundingBoxes.append(boundingBox)

    // Check for specific mapping
    let key = boundingBoxKey(boundingBox)
    if let embedding = embeddingsForBoundingBox[key] {
      return embedding
    }

    return defaultEmbedding
  }

  /// Resets all state for clean test setup.
  func reset() {
    embeddingsForBoundingBox = [:]
    defaultEmbedding = nil
    computeCallCount = 0
    computedBoundingBoxes = []
  }

  /// Configures an embedding to be returned for a specific bounding box.
  func setEmbedding(_ embedding: MockEmbedding, for boundingBox: CGRect) {
    let key = boundingBoxKey(boundingBox)
    embeddingsForBoundingBox[key] = embedding
  }

  private func boundingBoxKey(_ box: CGRect) -> String {
    // Round to 2 decimal places to avoid floating point comparison issues
    let x = (box.origin.x * 100).rounded() / 100
    let y = (box.origin.y * 100).rounded() / 100
    let w = (box.width * 100).rounded() / 100
    let h = (box.height * 100).rounded() / 100
    return "\(x),\(y),\(w),\(h)"
  }
}
