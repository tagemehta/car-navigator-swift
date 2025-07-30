/// TrackingManager
/// --------------
/// Implements the `VisionTracker` protocol using `VNTrackObjectRequest`s.
///
/// Duties per frame (invoked by `FramePipelineCoordinator` via services):
/// * Execute all active `VNTrackObjectRequest`s on the latest `CVPixelBuffer`.
/// * Cull finished requests (`isLastFrame`).
///
/// Other API:
/// * `addTracking(_:)` – enqueue a new vision tracking request for a detection.
/// * `clearTracking()` – stop and remove all active requests.
///
/// Notes:
/// The tracker itself does no lifecycle policies; `CandidateLifecycleService`
/// owns when to drop a candidate. This class purely forwards Vision results.
///
import CoreImage
import Foundation
import Vision

/// Manages object tracking using Vision framework
class TrackingManager: VisionTracker {
  /// Sequence handler for performing tracking requests
  private let sequenceHandler = VNSequenceRequestHandler()

  /// Currently active tracking requests
  private var activeTracking: [VNTrackObjectRequest] = []

  // legacy performTracking kept private
  private func performTracking(on buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation)
    -> Result<[VNTrackObjectRequest], Error>
  {
    guard !activeTracking.isEmpty else { return .success([]) }
    do {
      try sequenceHandler.perform(
        activeTracking,
        on: buffer,
        orientation: orientation
      )
      // Remove tracking requests that have completed
      activeTracking.removeAll { $0.isLastFrame }
      return .success(activeTracking)
    } catch {
      activeTracking.removeAll { $0.isLastFrame }
      clearTracking()
      print("Tracking error: \(error)")
      return .failure(error)
    }
  }

  /// Adds a tracking request
  /// - Parameter request: The tracking request to add
  func addTracking(_ request: VNTrackObjectRequest) {
    activeTracking.append(request)
  }

  /// Adds multiple tracking requests
  /// - Parameter requests: The tracking requests to add
  func addTracking(_ requests: [VNTrackObjectRequest]) {
    activeTracking.append(contentsOf: requests)
  }

  /// Legacy method for backward compatibility
  /// - Parameter request: The tracking request to add
  func addTrackingRequest(_ request: VNTrackObjectRequest) {
    addTracking(request)
  }

  /// Clears all active tracking requests
  /* Sets isLastFrame to true, so that vision knows to
     stop tracking. If they are removed then vision won't stop tracking them
     and you will get a too many objects in tracking error
  */
  func clearTracking() {
    activeTracking.forEach { $0.isLastFrame = true }
  }

  /// Clears all active tracking requests except the specified one
  /// - Parameter keep: The tracking request to keep
  func clearTrackingExcept(_ keep: VNTrackObjectRequest) {
    for req in activeTracking where req !== keep {
      req.isLastFrame = true
    }
  }

  /// Checks if there are any active tracking requests
  var hasActiveTracking: Bool {
    return !activeTracking.isEmpty
  }
  /// Creates a tracking request for the given observation
  /// - Parameters:
  ///   - observation: The observation to track
  ///   - handler: The completion handler for the tracking request
  /// - Returns: The tracking request
  func createTrackingRequest(
    for observation: VNDetectedObjectObservation
  ) -> VNTrackObjectRequest {
    let request = VNTrackObjectRequest(detectedObjectObservation: observation)
    request.trackingLevel = .accurate
    return request
  }

  // MARK: - VisionTracker
  func tick(
    pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, store: CandidateStore
  ) {
    switch performTracking(on: pixelBuffer, orientation: orientation) {
    case .success(let requests):
      for req in requests {
        guard let det = req.results?.first as? VNDetectedObjectObservation else { continue }
        let snap = store.snapshot()
        if let (id, _) = snap.first(where: { $0.value.trackingRequest === req }) {
          store.update(id: id) { cand in
            cand.lastBoundingBox = det.boundingBox
          }
        }
      }
    case .failure(_):
      break
    }
  }
}
