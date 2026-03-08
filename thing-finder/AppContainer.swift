//  AppContainer.swift
//  thing-finder
//
//  Central composition root that wires concrete service implementations together.
//  Keeps SwiftUI view-models lean and allows tests to swap services easily.
//
//  Usage (e.g. in CameraViewModel):
//    let coordinator = AppContainer.shared.makePipeline(classes: [...], description: "...")
//
//  Verification flow (simplified 2-layer architecture):
//    VerifierService → VerifierSelector → [TrafficEyeVerifier, TwoStepVerifier, AdvancedLLMVerifier]
//    Selection logic lives in VerifierSelector.selectVerifier()

import Foundation
import SwiftUI
import Vision

public final class AppContainer {
  static let shared = AppContainer()

  /// Shared debug overlay model for displaying verification errors and debug information
  let debugOverlayModel = DebugOverlayModel()

  private init() {}

  // Build a fully-wired coordinator for a given capture mode.
  func makePipeline(
    classes: [String],
    description: String,
    isParatransitMode: Bool = false
  ) -> FramePipelineCoordinator {
    let settings = Settings()
    // MARK: Concrete service wiring
    // 1. Detector
    let mlModel: VNCoreMLModel = {
      // Fallback to a lightweight default Vision model if your main CoreML file
      // isn't bundled yet; replace with actual.
      return try! VNCoreMLModel(for: yolo11n().model)
    }()
    let detector = DetectionManager(model: mlModel)

    // 2. Vision Tracker
    let tracker = TrackingManager()

    // 3. Drift repair using shared ImageUtilities
    let drift = DriftRepairService(imageUtils: ImageUtilities.shared)

    // 4. Verifier – VerifierSelector picks TrafficEye or LLM per-candidate
    let parsed = DescriptionParser.extractPlate(from: description)
    let needsOCR =
      classes.contains { ["car", "truck", "bus", "van"].contains($0.lowercased()) }
      && parsed.plate != nil
    let strategy: VerifierStrategy = isParatransitMode ? .paratransit : .hybrid
    let verifierConfig = VerificationConfig(
      expectedPlate: parsed.plate, shouldRunOCR: needsOCR, strategy: strategy)
    let verifier = VerifierService(
      targetTextDescription: description,
      imgUtils: ImageUtilities.shared,
      config: verifierConfig
    )

    // 5. Navigation manager (frame-driven)
    let nav = FrameNavigationManager(
      settings: settings,
      speaker: Speaker(settings: settings))

    // 6. Lifecycle manager
    let lifecycle = CandidateLifecycleService(imgUtils: ImageUtilities.shared)
    return FramePipelineCoordinator(
      detector: detector,
      tracker: tracker,
      driftRepair: drift,
      verifier: verifier,
      nav: nav,
      lifecycle: lifecycle,
      targetClasses: classes,
      targetDescription: description,
      settings: settings
    )
  }
}
