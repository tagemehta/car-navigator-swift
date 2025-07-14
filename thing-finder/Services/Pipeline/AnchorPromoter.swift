//  AnchorPromoter.swift
//  Converts 2-D Vision detections into ARKit anchors by ray-casting. Runs each
//  frame until every candidate owns an anchor.

import ARKit
import CoreVideo
import Foundation
import RealityKit
import Vision

/// Protocol so we can provide a mock in non-AR unit tests.
protocol AnchorPromoter {
  /// Attempt to promote candidates that still lack anchors.
  func tick(
    session: ARSession,
    arView: ARView,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect)
}

final class DefaultAnchorPromoter: AnchorPromoter {
  private let store: CandidateStore
  private let anchorManager: AnchorTrackingManager
  private let imgUtils: ImageUtilities

  init(store: CandidateStore, anchorManager: AnchorTrackingManager, imgUtils: ImageUtilities) {
    self.store = store
    self.anchorManager = anchorManager
    self.imgUtils = imgUtils
  }

  func tick(
    session: ARSession,
    arView: ARView,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect
  ) {
    // Iterate over a snapshot to avoid mutation while enumerating.
    guard
      store.candidates.values.first(where: { c in
        c.matchStatus == .matched
      }) != nil
    else {
      return
    }
    for candidate in store.candidates.values where candidate.anchorId == nil {
      // Convert normalised Vision rect → view rect using ImageUtilities helper
      let (_, viewRect) = imgUtils.unscaledBoundingBoxes(
        for: candidate.lastBoundingBox,
        imageSize: imageSize,
        viewSize: viewBounds.size,
        orientation: orientation)
      let viewPoint = CGPoint(x: viewRect.midX, y: viewRect.midY)
      guard
        let query = arView.makeRaycastQuery(
          from: viewPoint,
          allowing: .estimatedPlane,
          alignment: .any)
      else { continue }
      guard let result = session.raycast(query).first else {
        continue
      }
      let arAnchor = ARAnchor(transform: result.worldTransform)
      // Register anchor with AnchorTrackingManager so it appears in projection utilities
      anchorManager.registerPromotedAnchor(arAnchor, viewRect: viewRect)

      // Write UUID back into store on main thread
      DispatchQueue.main.async {
        self.store.update(id: candidate.id) { c in
          c.anchorId = arAnchor.identifier
        }
      }
    }
  }
}
