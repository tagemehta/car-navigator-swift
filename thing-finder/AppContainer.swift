//  AppContainer.swift
//  thing-finder
//
//  Central composition root that wires concrete service implementations together.
//  Keeps SwiftUI view-models lean and allows tests to swap services easily.
//
//  Usage (e.g. in CameraViewModel):
//    let coordinator = AppContainer.shared.makePipeline()
//
//  NOTE: Real implementations for detector/tracker/etc. are placeholders here—
//  you can keep using the existing DetectionManager et al. until we migrate.

import Foundation
import Vision

public final class AppContainer {
  static let shared = AppContainer()
  private init() {}

  // Build a fully-wired coordinator for a given capture mode.
  func makePipeline(classes: [String], description: String) -> FramePipelineCoordinator {
    let settings = Settings()
    // MARK: Concrete service wiring
    // 1. Detector
    let mlModel: VNCoreMLModel = {
      // Fallback to a lightweight default Vision model if your main CoreML file
      // isn’t bundled yet; replace with actual.
      return try! VNCoreMLModel(for: yolo11n().model)
    }()
    let detector = DetectionManager(model: mlModel)

    // 2. Vision Tracker
    let tracker = TrackingManager()

    // 3. Drift repair using shared ImageUtilities
    let drift = DriftRepairService(imageUtils: ImageUtilities.shared)

    // 4. Verifier – DefaultVerifierService wired with TrafficEyeVerifier
    // Extract potential license plate and remaining description
    let parsed = DescriptionParser.extractPlate(from: description)
    let needsOCR =
      classes.contains { ["car", "truck", "bus", "van"].contains($0.lowercased()) }
      && parsed.plate != nil
    let verifierConfig = VerificationConfig(
      expectedPlate: parsed.plate, shouldRunOCR: needsOCR, useCombinedVerifier: true)
    let verifier = VerifierService(
      verifier: TrafficEyeVerifier(
        targetClasses: classes, targetTextDescription: description, config: verifierConfig),
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
