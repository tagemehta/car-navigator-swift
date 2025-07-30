//  FeaturePrint+Similarity.swift
//  thing-finder
//
//  Helper to compute cosine similarity between two `VNFeaturePrintObservation`s.
//  Vision provides a built-in distance function but it’s ObjC-style (error-into-bool).
//  This wrapper returns a Float in 0…1 where 1 means identical.

import Vision

public enum FeaturePrintSimilarityError: Error {
  case cannotCompute
}

extension VNFeaturePrintObservation {
  /// Returns cosine similarity in 0…1 (1 = identical).
  public func cosineSimilarity(to other: VNFeaturePrintObservation) throws -> Float {
      // 1) get Euclidean “distance” between unit vectors
      var distance: Float = 0
      try self.computeDistance(&distance, to: other)

      // 2) recover true cosine in [–1,1]
      let cosθ = 1 - (distance*distance) / 2

      // 3) remap to [0,1]
      return (cosθ + 1) * 0.5
  }
}
