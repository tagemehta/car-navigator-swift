//  CameraViewModel.swift – slimmed-down version using FramePipelineCoordinator exclusively
//  All legacy Vision-only logic removed.

import ARKit
import Combine
import RealityKit
import SwiftUI
import Vision

/// Aggregates camera capture, per-frame coordination, and publishes bounding boxes for the overlay.
final class CameraViewModel: NSObject, ObservableObject, FrameProviderDelegate {

  // MARK: – Published output
  @Published var boundingBoxes: [BoundingBox] = []
  @Published var currentFPS: Double = 0

  // MARK: – Private state
  private let imgUtils: ImageUtilities
  private let fpsManager: FPSManager
  private let pipeline: FramePipelineCoordinator
  private let candidateStore = CandidateStore()
  private var cancellables = Set<AnyCancellable>()

  // Cached values updated every frame
  private var previewViewBounds: CGRect?
  private var imageSize: CGSize?
  // MARK: – Init
  init(dependencies: CameraDependencies) {
    self.imgUtils = dependencies.imageUtils
    // Build per-frame services
    let visionTracker = DefaultVisionTracker(store: candidateStore, imgUtils: imgUtils)
    // Temporary simple detector; replace with CoreML-powered DetectionManager when integrated
    let objectDetector: ObjectDetector = DetectionManager(
      model: try! VNCoreMLModel(for: yolo11n().model))
    let anchorTrackingManger = AnchorTrackingManager(imgUtils: imgUtils)
    let anchorPromoter = DefaultAnchorPromoter(
      store: candidateStore,
      anchorManager: anchorTrackingManger,
      imgUtils: imgUtils)
    let verifier = DefaultVerifierService(
      store: candidateStore,
      apiClient: LLMVerifier(
        targetClasses: dependencies.targetClasses,
        targetTextDescription: dependencies.targetTextDescription),
      imgUtils: imgUtils)
    let stateMachine = DetectionStateMachine()
    let navManager = NavigationManager()
    self.pipeline = FramePipelineCoordinator(
      visionTracker: visionTracker,
      anchorPromoter: anchorPromoter,
      anchorManager: anchorTrackingManger,
      verifier: verifier,
      objectDetector: objectDetector,
      targetClasses: dependencies.targetClasses,
      store: candidateStore,
      navManager: navManager,
      stateMachine: stateMachine,
      imgUtils: imgUtils)
    self.fpsManager = FPSManager()

    super.init()

    bindOutputs()
  }

  // MARK: – Binding
  private func bindOutputs() {
    pipeline.$presentation
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pres in
        self?.boundingBoxes = pres.boundingBoxes
      }
      .store(in: &cancellables)

    self.fpsManager.fpsPublisher
      .receive(on: DispatchQueue.main)
      .assign(to: &$currentFPS)
  }

  // MARK: – FrameProviderDelegate
  func processFrame(
    _ provider: any FrameProvider,
    frame: ARFrame,
    buffer: CVPixelBuffer
  ) {
    guard let session = provider.session else { return }
    self.fpsManager.updateFPSCalculation()
    let orientation = imgUtils.cgOrientation(
      for: UIInterfaceOrientation(UIDevice.current.orientation))
    if imageSize == nil {
      imageSize = CGSize(
        width: Int(CVPixelBufferGetWidth(buffer)), height: Int(CVPixelBufferGetHeight(buffer)))
    }
    if previewViewBounds == nil {
      previewViewBounds = provider.previewView.bounds
    }
    let arView = provider.previewView as? ARView
    pipeline.process(
      frame: frame,
      session: session,
      arView: arView,
      pixelBuffer: buffer,
      orientation: orientation,
      viewBounds: previewViewBounds!,
      imageSize: imageSize!)
  }

  public func handleOrientationChange() {
    imageSize = nil
    previewViewBounds = nil
  }
}
