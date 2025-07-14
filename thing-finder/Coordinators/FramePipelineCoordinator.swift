//  FramePipelineCoordinator.swift
//  Coordinates per-frame services, state machine, and presentation.

import ARKit
import Combine
import Foundation
import RealityKit
import SwiftUICore
import Vision

/// Value object emitted each frame for UI consumption.
struct FramePresentation {
  let boundingBoxes: [BoundingBox]
  let phase: DetectionPhase
}

final class FramePipelineCoordinator {
  // MARK: Dependencies
  private let visionTracker: VisionTracker
  private let anchorPromoter: AnchorPromoter
  private let anchorManager: AnchorTrackingManager
  private let verifier: VerifierService
  private let imgUtils: ImageUtilities
  private let objectDetector: ObjectDetector
  private let targetClasses: [String]
  private let store: CandidateStore
  private let navManager: NavigationManager
  private var stateMachine: DetectionStateMachine

  // MARK: Publishers
  @Published private(set) var presentation: FramePresentation = .init(
    boundingBoxes: [], phase: .searching)

  private var cancellables = Set<AnyCancellable>()

  init(
    visionTracker: VisionTracker,
    anchorPromoter: AnchorPromoter,
    anchorManager: AnchorTrackingManager,
    verifier: VerifierService,
    objectDetector: ObjectDetector,
    targetClasses: [String],
    store: CandidateStore,
    navManager: NavigationManager,
    stateMachine: DetectionStateMachine,
    imgUtils: ImageUtilities
  ) {
    self.visionTracker = visionTracker
    self.anchorPromoter = anchorPromoter
    self.anchorManager = anchorManager
    self.verifier = verifier
    self.store = store
    self.navManager = navManager
    self.stateMachine = stateMachine
    self.imgUtils = imgUtils
    self.objectDetector = objectDetector
    self.targetClasses = targetClasses

  }

  // MARK: Frame Tick
  func process(
    frame: ARFrame,
    session: ARSession,
    arView: ARView?,
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    viewBounds: CGRect,
    imageSize: CGSize
  ) {
    // 0. Detection – create or update candidates
    if case .searching = stateMachine.phase {
      let detections = objectDetector.detect(
        pixelBuffer,
        { obs in
          guard let label = obs.labels.first?.identifier else { return false }
          return targetClasses.contains(label)
        }, orientation: orientation)

      // Create tracking requests for new detections
      for det in detections {
        // Deduplicate by IoU overlap with existing candidates
        let exists = store.candidates.values.contains { cand in
          cand.lastBoundingBox.iou(with: det.boundingBox) > 0.5
        }
        if !exists {
          let trReq = VNTrackObjectRequest(detectedObjectObservation: det)
          trReq.trackingLevel = .accurate
          let candidate = Candidate(trackingRequest: trReq, boundingBox: det.boundingBox)
          store.upsert(candidate)
        }
      }
    }

    // 1. Vision tracking update (runs off-thread inside implementation)
    visionTracker.tick(
      pixelBuffer: pixelBuffer,
      orientation: orientation)

    // 2. Anchor promotion
    if let arView {
      anchorPromoter.tick(
        session: session,
        arView: arView,
        orientation: orientation,
        imageSize: imageSize,
        viewBounds: viewBounds)
    }

    // 3. Verifier LLM
    verifier.tick(
      pixelBuffer: pixelBuffer,
      orientation: orientation,
      imageSize: imageSize,
      viewBounds: viewBounds)

    // 4. Update detection phase
    stateMachine.update(snapshot: Array(store.candidates.values))
    let phase = stateMachine.phase
    print(phase)
    // 5. Produce bounding boxes for UI: convert to viewRect
    let boxes: [BoundingBox] = store.candidates.values.map { cand in
      let color: Color?
      switch cand.matchStatus {
      case .matched:
        if cand.anchorId == nil {
          color = .purple
        } else {
          color = .green
        }

      case .unknown:
        color = .yellow

      case .rejected:
        color = .red

      case .waiting:
        color = .blue

      }
      let (_, viewRect) = imgUtils.unscaledBoundingBoxes(
        for: cand.lastBoundingBox,
        imageSize: imageSize,
        viewSize: viewBounds.size,
        orientation: orientation)
      return BoundingBox(
        imageRect: cand.lastBoundingBox,
        viewRect: viewRect,
        label: cand.id.uuidString,
        color: color!,
        alpha: 0.85
      )
    }
    if case .found(let id, _) = phase {
      let (depth, rect) = anchorManager.navigateToAnchor(
        id, frame: frame, viewBounds: viewBounds)
      navManager.handle(.found, box: rect, distanceMeters: Double(depth))
    }

    presentation = FramePresentation(boundingBoxes: boxes, phase: phase)
  }

  // MARK: Reset helpers
  func clear() {
    store.clear()
    // TODO: remove anchors from session if needed
  }
}
