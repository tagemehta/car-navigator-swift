/*import Combine
import Foundation
import Vision

/// Protocol defining state management functionality
protocol StateController {
  /// Current detection state
  var detectionState: DetectionState { get }

  /// Publisher for the detection state
  var detectionStatePublisher: AnyPublisher<DetectionState, Never> { get }

  /// Processes state transitions based on identified objects
  /// - Parameters:
  ///   - identifiedObjects: Array of identified objects
  ///   - boundingBoxes: Current bounding boxes to display
  ///   - updateBoundingBoxes: Closure to update bounding boxes in the UI
  func processStateTransitions(
    identifiedObjects: [IdentifiedObject],
    boundingBoxes: [BoundingBox],
    updateBoundingBoxes: @escaping ([BoundingBox]) -> Void
  )

  /// Processes a found target
  /// - Parameters:
  ///   - target: The identified object being tracked
  ///   - observation: The detected object observation
  ///   - boundingBox: The bounding box for the target
  ///   - distanceMeters: The estimated distance to the target in meters
  ///   - updateBoundingBoxes: Closure to update bounding boxes in the UI
  ///   - clearTracking: Closure to clear active tracking
  /// - Returns: Updated target with new state
  func processFoundTarget(
    target: IdentifiedObject,
    observation: VNDetectedObjectObservation?,
    boundingBox: BoundingBox?,
    distanceMeters: Double?,
    updateBoundingBoxes: @escaping ([BoundingBox]) -> Void,
    clearTracking: @escaping () -> Void
  ) -> IdentifiedObject?

  /// Handles the result of an LLM verification for a candidate
  /// - Parameters:
  ///   - candidate: The candidate object that was verified
  ///   - matched: Whether the verifier matched the target description
  ///   - inflightRemaining: Flag indicating if other verification requests are still in flight
  ///   - clearTracking: Closure to clear all tracking requests
  ///   - clearTrackingExcept: Closure to clear all tracking requests except a given request
  /// - Returns: The new detection state after processing the verification result
  func handleVerificationResult(
    candidate: IdentifiedObject,
    matched: Bool,
    inflightRemaining: Bool,
    clearTracking: @escaping () -> Void,
    clearTrackingExcept: @escaping (VNTrackObjectRequest) -> Void
  ) -> DetectionState
}

/// Default implementation of StateController
class DefaultStateController: StateController, ObservableObject {
  /// Current detection state
  @Published var detectionState: DetectionState = .searching

  /// Publisher for the detection state
  var detectionStatePublisher: AnyPublisher<DetectionState, Never> {
    $detectionState.eraseToAnyPublisher()
  }

  /// Navigation manager for handling navigation events
  private let navigationManager: NavigationManager

  /// Settings for state transitions
  private let settings: Settings

  /// Initializes the StateController with required dependencies
  /// - Parameters:
  ///   - navigationManager: Navigation manager for handling navigation events
  ///   - settings: Settings for state transitions
  init(navigationManager: NavigationManager, settings: Settings) {
    self.navigationManager = navigationManager
    self.settings = settings
  }

  /// Processes state transitions based on identified objects
  /// - Parameters:
  ///   - identifiedObjects: Array of identified objects
  ///   - boundingBoxes: Current bounding boxes to display
  ///   - updateBoundingBoxes: Closure to update bounding boxes in the UI
  func processStateTransitions(
    identifiedObjects: [IdentifiedObject],
    boundingBoxes: [BoundingBox],
    updateBoundingBoxes: @escaping ([BoundingBox]) -> Void
  ) {
    // Update state if we're searching and found candidates
    if case .searching = detectionState {
      identifiedObjects.count > 0 ? detectionState = .verifying(candidates: identifiedObjects) : ()
    }

    // Update UI with bounding boxes if needed
    if detectionState.displayAllBoxes {
      updateBoundingBoxes(boundingBoxes)
    }
  }

  /// Processes a found target
  /// - Parameters:
  ///   - target: The identified object being tracked
  ///   - observation: The detected object observation
  ///   - boundingBox: The bounding box for the target
  ///   - distanceMeters: The estimated distance to the target in meters
  ///   - updateBoundingBoxes: Closure to update bounding boxes in the UI
  ///   - clearTracking: Closure to clear active tracking
  /// - Returns: Updated target with new state
  func processFoundTarget(
    target: IdentifiedObject,
    observation: VNDetectedObjectObservation?,
    boundingBox: BoundingBox?,
    distanceMeters: Double?,
    updateBoundingBoxes: @escaping ([BoundingBox]) -> Void,
    clearTracking: @escaping () -> Void
  ) -> IdentifiedObject? {
    var targetMut = target
    targetMut.lifetime += 1

    // Check if we still have a valid observation and the target hasn't expired
    guard let observation = observation, targetMut.lifetime < settings.targetLifetime else {
      handleTargetLostOrExpired(target: targetMut, clearTracking: clearTracking)
      return nil
    }

    // Check if the target has drifted
    if isTargetDrifted(target: target, observation: observation) {
      handleTargetDrifted(target: targetMut, clearTracking: clearTracking)
      return nil
    }

    // Update target with new bounding box
    targetMut.lastBoundingBox = observation.boundingBox

    // Update UI with the bounding box
    if let box = boundingBox {
      updateBoundingBoxes([box])
    }

    // Handle navigation update
    navigationManager.handle(
      NavEvent.found,
      box: observation.boundingBox,
      distanceMeters: distanceMeters
    )

    // Update state
    detectionState = .found(target: targetMut)
    return targetMut
  }

  func handleVerificationResult(
    candidate: IdentifiedObject,
    matched: Bool,
    inflightRemaining: Bool,
    clearTracking: @escaping () -> Void,
    clearTrackingExcept: @escaping (VNTrackObjectRequest) -> Void
  ) -> DetectionState {
    // Only promote to .found when LLM matched AND candidate already has an ARKit anchor
    let hasAnchor = candidate.anchorId != nil

    if matched && hasAnchor {
      // If matched, keep only this candidate's tracking request
      clearTrackingExcept(candidate.trackingRequest)
      detectionState = .found(target: candidate)
      navigationManager.handle(.found)
    } else if !inflightRemaining {
      // Only reset to searching when no more verification requests are pending
      detectionState = .searching
      navigationManager.handle(.noMatch)
      clearTracking()
    }
    return detectionState
  }

  /// Resets detection state to searching (used when anchor lost)
  func resetToSearching() {
    detectionState = .searching
    navigationManager.handle(.lost)
  }

  /// Determines if a target has drifted from its expected position
  /// - Parameters:
  ///   - target: The target being tracked
  ///   - observation: The current observation of the target
  /// - Returns: True if the target has drifted, false otherwise
  private func isTargetDrifted(target: IdentifiedObject, observation: VNDetectedObjectObservation)
    -> Bool
  {
    let prevBox = target.lastBoundingBox ?? observation.boundingBox
    let iouPrev = prevBox.iou(with: observation.boundingBox)
    let diagonal = Float(hypot(prevBox.width, prevBox.height))
    let centreShift =
      Float(
        hypot(
          observation.boundingBox.midX - prevBox.midX,
          observation.boundingBox.midY - prevBox.midY
        )
      ) / diagonal
    let areaPrev = Float(prevBox.width * prevBox.height)
    let areaNew = Float(observation.boundingBox.width * observation.boundingBox.height)
    let areaShift = abs(areaNew - areaPrev) / areaPrev

    return iouPrev < settings.minIouThreshold || centreShift > Float(settings.maxCenterShift)
      || areaShift > Float(settings.maxAreaShift)
      || observation.confidence < Float(settings.minTrackingConfidence)
  }

  /// Handles a target that has been lost or expired
  /// - Parameters:
  ///   - target: The target that was lost or expired
  ///   - clearTracking: Closure to clear active tracking
  private func handleTargetLostOrExpired(
    target: IdentifiedObject, clearTracking: @escaping () -> Void
  ) {
    if target.lifetime >= settings.targetLifetime {
      navigationManager.handle(NavEvent.expired)
      self.detectionState = .searching
      clearTracking()
    } else if target.lostInTracking > settings.maxLostFrames {
      navigationManager.handle(NavEvent.lost)
      self.detectionState = .searching
      clearTracking()
    } else {
      var targetMut = target
      targetMut.box.label += "?"
      targetMut.lostInTracking += 1
      self.detectionState = .found(target: targetMut)
    }
  }

  /// Handles a target that has drifted
  /// - Parameters:
  ///   - target: The target that drifted
  ///   - clearTracking: Closure to clear active tracking
  private func handleTargetDrifted(target: IdentifiedObject, clearTracking: @escaping () -> Void) {
    if target.lostInTracking >= settings.maxLostFrames {
      navigationManager.handle(NavEvent.lost)
      self.detectionState = .searching
      clearTracking()
    } else {
      var targetMut = target
      targetMut.box.label += "?"
      targetMut.lostInTracking += 1
      self.detectionState = .found(target: targetMut)
    }
  }
}

*/
