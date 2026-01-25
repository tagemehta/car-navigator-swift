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

  /// Maps TrackingRequest.id to the underlying VNTrackObjectRequest for Vision operations
  private var requestMapping: [UUID: VNTrackObjectRequest] = [:]

  /// Currently active Vision tracking requests
  private var activeTracking: [VNTrackObjectRequest] {
    Array(requestMapping.values)
  }

  // legacy performTracking kept private
  private func performTracking(on buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation)
    -> Result<[VNTrackObjectRequest], Error>
  {
    guard !requestMapping.isEmpty else { return .success([]) }
    let requests = Array(requestMapping.values)
    do {
      try sequenceHandler.perform(
        requests,
        on: buffer,
        orientation: orientation
      )
      // Remove tracking requests that have completed
      for (id, req) in requestMapping where req.isLastFrame {
        requestMapping.removeValue(forKey: id)
      }
      return .success(Array(requestMapping.values))
    } catch {
      for req in requestMapping.values {
        req.isLastFrame = true
      }
      requestMapping.removeAll()
      print("Tracking error: \(error)")
      return .failure(error)
    }
  }

  /// Registers a TrackingRequest wrapper for tracking
  /// - Parameter wrapper: The TrackingRequest wrapper containing the VNTrackObjectRequest
  func addTracking(_ wrapper: TrackingRequest) {
    guard let visionRequest = wrapper.visionRequest else { return }
    requestMapping[wrapper.id] = visionRequest
  }

  /// Clears all active tracking requests
  func clearTracking() {
    for req in requestMapping.values {
      req.isLastFrame = true
    }
  }

  /// Clears all active tracking requests except the one with the specified ID
  /// - Parameter keepId: The TrackingRequest.id to keep
  func clearTrackingExcept(_ keepId: UUID) {
    for (id, req) in requestMapping where id != keepId {
      req.isLastFrame = true
    }
  }

  /// Checks if there are any active tracking requests
  var hasActiveTracking: Bool {
    return !requestMapping.isEmpty
  }

  /// Creates a TrackingRequest wrapper for the given observation
  /// - Parameter observation: The observation to track
  /// - Returns: The TrackingRequest wrapper
  func createTrackingRequest(
    for observation: VNDetectedObjectObservation
  ) -> TrackingRequest {
    let request = VNTrackObjectRequest(detectedObjectObservation: observation)
    request.trackingLevel = .accurate
    return TrackingRequest(from: request)
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
        // Find candidate by matching the VNTrackObjectRequest reference
        if let (id, _) = snap.first(where: { cand in
          guard let visionReq = cand.value.trackingRequest.visionRequest else { return false }
          return visionReq === req
        }) {
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
