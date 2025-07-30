//  CGRect+IoU.swift
//  thing-finder
//
//  Lightweight helper to compute Intersection-over-Union between two rects in
//  normalized coordinates.  Copied from DetectionManager but extracted to a
//  shared utility so `CandidateStore` and other pure-Swift modules can use it
//  without importing heavy Vision code.

import CoreGraphics

public extension CGRect {
  /// Compute IoU between `self` and `other`.
  /// - Returns: Value in 0…1 where 1 is perfect overlap.
  func iou(with other: CGRect) -> CGFloat {
    let intersection = self.intersection(other)
    guard !intersection.isNull else { return 0 }
    let interArea = intersection.width * intersection.height
    let unionArea = self.width * self.height + other.width * other.height - interArea
    return unionArea == 0 ? 0 : interArea / unionArea
  }
}
