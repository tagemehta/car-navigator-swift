import Foundation
import Vision
import CoreImage

/// Coordinator that owns the lifecycle of `VNTrackObjectRequest`s.
/// It encapsulates the quirks of properly cancelling Vision tracking requests:
/// 1. You must mark `isLastFrame` (AKA `isLastFrame`) **true** on the request.
/// 2. You still need to run the request for ONE more frame; only then will Vision
///    release its internal references and the request can be removed safely.
///
/// Usage pattern per frame:
/// ```swift
/// visionTracker.update(buffer: pixelBuffer, orientation: orientation)
/// ```
/// You can call `track(observation:)` to start a new track and
/// `cancelAll()` to mark every request for removal.
final class VisionTrackingCoordinator {

  // MARK: - Stored properties
  private var activeRequests: [VNTrackObjectRequest] = []
  /// Requests that had `isLastFrame` set during the *previous* frame. These will be
  /// inspected after the next update; if their results contain an error they are dropped.
  private var retiringRequests: [VNTrackObjectRequest] = []
  private let sequenceHandler = VNSequenceRequestHandler()

  // MARK: - Public API
  /// Start tracking a new observation. Returns the newly created request so callers can store it
  /// if they need a reference.
  @discardableResult
  func track(observation: VNRecognizedObjectObservation) -> VNTrackObjectRequest {
    let request = VNTrackObjectRequest(detectedObjectObservation: observation)
    request.trackingLevel = .accurate
    activeRequests.append(request)
    return request
  }

  /// Per-frame update. Runs all active and retiring requests.
  func update(buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
    // Remove any requests that finished retiring last frame (error == .objectTrackingFailed).
    if !retiringRequests.isEmpty {
      activeRequests.removeAll { req in retiringRequests.contains(req) }
      retiringRequests.removeAll()
    }

    guard !activeRequests.isEmpty else { return }
    do {
      try sequenceHandler.perform(activeRequests, on: buffer, orientation: orientation)
    } catch {
      // If Vision throws we simply log and keep going; callers can decide next steps.
      print("VisionTrackingCoordinator: VNSequenceRequestHandler error \(error)")
    }

    // Move any requests that have been asked to stop into retiringRequests so they get
    // one more evaluation cycle before true removal.
    for req in activeRequests where req.isLastFrame {
      retiringRequests.append(req)
    }
  }

  /// Marks **all** active requests for removal. They will be cleared automatically after the next
  /// `update` call.
  func cancelAll() {
    for req in activeRequests {
      req.isLastFrame = true
    }
    // They will be moved to retiringRequests during the next update.
  }
}
