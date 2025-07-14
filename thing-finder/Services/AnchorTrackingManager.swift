//  AnchorTrackingManager.swift
//  thing-finder
//
//  Phase-1 additive ARKit-anchor tracking support. Legacy Vision tracking remains intact.
//  Created automatically by Cascade on 2025-07-12.

import ARKit
import Foundation
import SwiftUI
import Vision

/// Lightweight container describing an anchor we are interested in and its UI state.
struct TrackedAnchor: Identifiable {
  public let id: UUID
  public var anchor: ARAnchor
  public var boundingBox: BoundingBox
  /// Indicates whether the anchor is merely a detection candidate awaiting LLM verification.
  public var isCandidate: Bool
}

/// Manages the lifecycle of anchors created for detected objects.
/// Phase-1: basic create & update; more sophisticated logic (confidence, relocalisation) can be added later.
class AnchorTrackingManager {

  // MARK: ‑ Dependencies
  private let imgUtils: ImageUtilities

  // MARK: ‑ State
  private var tracked: [UUID: TrackedAnchor] = [:]
  /// True when at least one anchor is not a candidate (i.e. successfully ray-cast)
  public var hasActiveAnchors: Bool { tracked.values.contains { !$0.isCandidate } }
  public var allTracked: [TrackedAnchor] { Array(tracked.values) }

  init(imgUtils: ImageUtilities) {
    self.imgUtils = imgUtils
  }

  // MARK: ‑ Public API

  /// Register an anchor that was created externally (e.g. by AnchorPromoter).
  /// The manager will start tracking and projecting it like any other.
  func registerPromotedAnchor(_ anchor: ARAnchor, viewRect: CGRect) {
    let box = BoundingBox(imageRect: .zero, viewRect: viewRect, label: "", color: .yellow)
    _ = store(anchor: anchor, candidate: false, templateBox: box)
  }

  /// Create an ARAnchor for a Vision observation.
  /// Attempts to ray-cast from the 2-D centre of the detection into the real world;
  /// if no surface is hit we fall back to a point 30 cm in front of the camera.
  func createAnchor(
    for observation: VNRecognizedObjectObservation,
    boundingBox: BoundingBox,
    in frame: ARFrame,
    session: ARSession
  ) -> TrackedAnchor {

    // Use centre of already-scaled view rect from boundingBox (created with unscaledBoundingBoxes)
    let viewPoint = CGPoint(x: boundingBox.viewRect.midX, y: boundingBox.viewRect.midY)
    let query = frame.raycastQuery(
      from: viewPoint,
      allowing: .estimatedPlane,
      alignment: .any
    )
    if let result = session.raycast(query).first {
      return store(
        anchor: ARAnchor(transform: result.worldTransform), candidate: true,
        templateBox: boundingBox)
    }

    // Fallback – place anchor 0.3 m in front of the camera
    let cameraTransform = frame.camera.transform
    let forward = simd_mul(cameraTransform, SIMD4(0, 0, -0.3, 1))
    var transform = matrix_identity_float4x4
    transform.columns.3 = forward
    return store(anchor: ARAnchor(transform: transform), candidate: true, templateBox: boundingBox)
  }

  /// Update cached anchor transforms every frame.
  func updateAnchors(from frame: ARFrame) {
    // Remove anchors that ARKit has culled (tracking lost)
    tracked = tracked.filter { uuid, trackedAnchor in
      frame.anchors.contains(where: { $0.identifier == uuid })
    }

    for uuid in tracked.keys {
      if let arAnchor = frame.anchors.first(where: { $0.identifier == uuid }) {
        tracked[uuid]?.anchor = arAnchor
      }
    }
  }

  /// Project anchor into screen space and build BoundingBox.
  func projectAnchor(
    _ trackedAnchor: TrackedAnchor, in frame: ARFrame, viewBounds: CGRect, label: String,
    color: Color
  ) -> BoundingBox? {
    guard
      let rect = imgUtils.project(
        anchor: trackedAnchor.anchor, frame: frame, viewBounds: viewBounds)
    else {
      return nil
    }
    return BoundingBox(imageRect: .zero, viewRect: rect, label: label, color: color)
  }

  /// Project all currently tracked anchors to screen-space bounding boxes
  func projectedBoxes(in frame: ARFrame, viewBounds: CGRect) -> [BoundingBox] {
    tracked.values.compactMap { trackedAnchor in
      projectAnchor(
        trackedAnchor, in: frame, viewBounds: viewBounds, label: trackedAnchor.boundingBox.label,
        color: trackedAnchor.boundingBox.color)
    }
  }
  /// https://stackoverflow.com/questions/50937214/arkit-getting-distance-from-camera-to-anchor
  func navigateToAnchor(_ id: UUID, frame: ARFrame, viewBounds: CGRect) -> (
    distance: Float, rect: CGRect
  ) {
    guard let anchor = tracked[id] else { fatalError("Anchor not found") }
    let transform = anchor.anchor.transform
    let cameraTransform = transform.inverse
    let cameraPosition = cameraTransform.columns.3
    let anchorPosition = transform.columns.3
    let distance = simd_length(cameraPosition - anchorPosition)
    let box = projectAnchor(
      anchor, in: frame, viewBounds: viewBounds, label: anchor.boundingBox.label,
      color: anchor.boundingBox.color)!
    return (
      distance,
      VNNormalizedRectForImageRect(box.viewRect, Int(viewBounds.width), Int(viewBounds.height))
    )
  }

  /// Attempt to upgrade candidate anchors by re-raycasting each frame.
  /// If a candidate raycast now hits a real surface, promote it and mark `isCandidate = false`.
  public func attemptUpgradeCandidates(in frame: ARFrame, session: ARSession) {
    for (id, trackedAnchor) in tracked where trackedAnchor.isCandidate {
      let viewPoint = CGPoint(
        x: trackedAnchor.boundingBox.viewRect.midX,
        y: trackedAnchor.boundingBox.viewRect.midY)
      let query = frame.raycastQuery(
        from: viewPoint,
        allowing: .estimatedPlane,
        alignment: .any)
      guard let hit = session.raycast(query).first else { continue }
      // Replace stored anchor with upgraded one
      tracked[id] = TrackedAnchor(
        id: id,
        anchor: ARAnchor(transform: hit.worldTransform),
        boundingBox: trackedAnchor.boundingBox,
        isCandidate: false)
    }
  }

  // MARK: ‑ Helpers
  @discardableResult
  private func store(anchor: ARAnchor, candidate: Bool, templateBox: BoundingBox) -> TrackedAnchor {
    let trackedAnchor = TrackedAnchor(
      id: anchor.identifier,
      anchor: anchor,
      boundingBox: templateBox,
      isCandidate: candidate)
    tracked[trackedAnchor.id] = trackedAnchor
    return trackedAnchor
  }
}
