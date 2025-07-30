//  FramePipelineCoordinator.swift
//  thing-finder
//
//  Coordinates the per-frame flow:
//  1. Detection → new Vision observations
//  2. VisionTracker tick → updates candidate bounding boxes
//  3. DriftRepairService tick (every N frames)
//  4. VerifierService tick (LLM)
//  5. State reducer → DetectionPhase update
//  6. NavigationManager reacts
//  7. Publishes FramePresentation for UI
//
//  NOTE: This is an initial skeleton focused on wiring. Concrete queue/
//  threading decisions will come later.

import Combine
import CoreMedia
import Foundation
import Vision

/// High-level value passed to SwiftUI for rendering overlays.
public struct FramePresentation {
  public let phase: DetectionPhase
  public let candidates: [Candidate]
}

/// Dependency-injected coordinator – pure Swift logic, testable.
public final class FramePipelineCoordinator: ObservableObject {
  // MARK: Services
  private let detector: ObjectDetector
  private let tracker: VisionTracker
  private let driftRepair: DriftRepairServiceProtocol
  private let verifier: VerifierServiceProtocol
  private let nav: NavigationSpeaker
  private let store: CandidateStore
  private let stateMachine: DetectionStateMachine = DetectionStateMachine()
  private let lifecycle: CandidateLifecycleServiceProtocol

  private let imgUtils: ImageUtilities = ImageUtilities.shared

  private let targetClasses: [String]
  private let targetDescription: String
  private let settings: Settings
  // MARK: Publishers
  @Published public private(set) var presentation: FramePresentation?

  // MARK: Init
  public init(
    detector: ObjectDetector,
    tracker: VisionTracker,
    driftRepair: DriftRepairServiceProtocol,
    verifier: VerifierServiceProtocol,
    nav: NavigationSpeaker,
    store: CandidateStore = CandidateStore(),
    lifecycle: CandidateLifecycleServiceProtocol,
    targetClasses: [String],
    targetDescription: String,
    settings: Settings
  ) {
    self.detector = detector
    self.tracker = tracker
    self.driftRepair = driftRepair
    self.verifier = verifier
    self.nav = nav
    self.store = store
    self.lifecycle = lifecycle
    self.targetClasses = targetClasses
    self.targetDescription = targetDescription
    self.settings = settings
  }

  // MARK: Per-frame entry point
  public func process(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    imageSize: CGSize,
    viewBounds: CGRect,
    depthAt: @escaping (CGPoint) -> Float?,
    captureType: CaptureSourceType
  ) {
    // 1. Detection (filter always true for now)
    let detections = detector.detect(
      pixelBuffer,
      filter: { obs in
        targetClasses.contains(obs.labels.first?.identifier ?? "")
      }, orientation: orientation)

    // 2. Vision tracking updates existing candidates
    tracker.tick(pixelBuffer: pixelBuffer, orientation: orientation, store: store)

    // 3. Drift repair (may/no-op depending on stride)
    driftRepair.tick(
      pixelBuffer: pixelBuffer,
      orientation: orientation,
      imageSize: imageSize,
      viewBounds: viewBounds,
      detections: detections,
      store: store
    )
    let isLost = lifecycle.tick(
      pixelBuffer: pixelBuffer, orientation: orientation, imageSize: imageSize,
      detections: detections, store: store)
    // 5. Verifier tick (sets matchStatus)
    verifier.tick(
      pixelBuffer: pixelBuffer,
      orientation: orientation,
      imageSize: imageSize,
      viewBounds: viewBounds,
      store: store
    )

    // If all candidates were removed, you may reset trackers if desired.
    if isLost {
      print("All candidates lost – resetting trackers")
    }

    // 6. Update global phase
    let snapshot = store.snapshot()
    var machine = stateMachine
    machine.update(snapshot: Array(snapshot.values))
    let phase = machine.phase

    // 7.5 Determine target bounding box & approximate distance for navigation cues
    var targetBBox: CGRect?
    switch phase {
    case .found(let id):
      targetBBox = store[id]?.lastBoundingBox
    case .verifying(let ids):
      // Prefer a partial match if any of the verifying IDs are currently partial
      if let partial = snapshot.values.first(where: {
        ids.contains($0.id) && $0.matchStatus == .partial
      }), settings.allowPartialNavigation {
        targetBBox = partial.lastBoundingBox
      }
    default:
      break
    }

    var targetDistance: Double?
    if let box = targetBBox {
      // Sample depth at the box centre using the supplied depthAt closure.
      let center: CGPoint
      switch captureType {
      case .avFoundation, .videoFile:
        // Convert view-rect back to normalized image rect for AVF buffers
        let (imageRect, _) = imgUtils.unscaledBoundingBoxes(
          for: box,
          imageSize: imageSize,
          viewSize: imageSize,
          orientation: orientation)
        let normImageRect = VNNormalizedRectForImageRect(
          imageRect, Int(imageSize.width), Int(imageSize.height))
        center = CGPoint(x: normImageRect.midX, y: normImageRect.midY)
      case .arKit:
        center = CGPoint(x: box.midX, y: box.midY)
      }
      if let d = depthAt(center) {
        targetDistance = Double(d)
      }
      print("Target distance: \(targetDistance ?? 0)")
    }

    // 7.5 Navigation tick
    nav.tick(
      at: Date(),
      candidates: Array(snapshot.values),
      targetBox: targetBBox,
      distance: targetDistance)

    // 8. Publish for UI
    presentation = FramePresentation(
      phase: phase,
      candidates: Array(snapshot.values)
    )
  }
}
