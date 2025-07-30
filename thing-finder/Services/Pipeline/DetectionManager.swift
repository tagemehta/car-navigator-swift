/// DetectionManager
/// -----------------
/// Concrete implementation of `ObjectDetector` wrapping a CoreML model via Vision.
///
/// Responsibilities per frame:
/// * Run `VNCoreMLRequest` against the camera `CVPixelBuffer`.
/// * Apply caller-supplied filter to limit classes of interest.
/// * Return `VNRecognizedObjectObservation` array to the pipeline.
///
/// Additional helpers:
/// * `stableDetections(...)` – rudimentary temporal smoothing by counting how many
///   consecutive frames a bounding box persists (based on IoU matching).
///
/// Thread-safety: Intended to be called from a background queue; mutates
/// `lastDetections` & `detectionStability` internally but not shared across threads.
///
import AVFoundation
// Extension to handle photo library access
import Photos
import SwiftUI
import Vision

class DetectionManager: ObjectDetector {
  private var mlModel: VNCoreMLModel
  // last processed frame
  private var lastDetections: [VNRecognizedObjectObservation] = []
  /// Stores consecutive-frame counts as a cache
  private var detectionStability: [CGRect: Int] = [:]
  private lazy var visionRequest: VNCoreMLRequest = {
    let request = VNCoreMLRequest(
      model: mlModel

    )
    // NOTE: BoundingBoxView object scaling depends on request.imageCropAndScaleOption https://developer.apple.com/documentation/vision/vnimagecropandscaleoption
    request.imageCropAndScaleOption = .scaleFill  // .scaleFit, .scaleFill, .centerCrop
    return request
  }()
  init(model: VNCoreMLModel) {
    self.mlModel = model
  }

  public func detect(
    _ imageBuffer: CVPixelBuffer,
    filter detectionFilterFn: (VNRecognizedObjectObservation) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [VNRecognizedObjectObservation] {

    let handler = VNImageRequestHandler(
      cvPixelBuffer: imageBuffer, orientation: orientation,
      options: [:])
    do {
      //       // MARK: - Process image with Image2Image model
      //            lazy var visionRequest2: VNCoreMLRequest = {
      //              do {
      //                let visionModel = try VNCoreMLModel(for: Image2Image().model)
      //
      //                let request = VNCoreMLRequest(
      //                  model: visionModel,
      //                  completionHandler: { [weak self] request, error in
      //                    if let results = request.results as? [VNPixelBufferObservation],
      //                      let pixelBuffer = results.first?.pixelBuffer
      //                    {
      //
      //                      let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
      //                      let context = CIContext()
      //
      //                      if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
      //                        let uiImage = UIImage(cgImage: cgImage)
      //                        uiImage.saveToPhotoLibrary(completion: { success, error in
      //                          if success {
      //                            print("✅ Successfully saved image to photo library")
      //                          } else if let error = error {
      //                            print(
      //                              "❌ Error saving image to photo library: \(error.localizedDescription)")
      //                          }
      //                        })
      //                      }
      //                    }
      //                  }
      //                )
      //
      //                request.imageCropAndScaleOption = .scaleFill
      //                return request
      //              } catch {
      //                fatalError("Failed to create VNCoreMLModel: \(error)")
      //              }
      //            }()
      //
      //            //      // Uncomment the line below to enable image processing and saving
      //            try handler.perform([visionRequest2])
      try handler.perform([visionRequest])
      guard let results = visionRequest.results as? [VNRecognizedObjectObservation] else {
        return []
      }
      let filteredResults = results.filter(detectionFilterFn)
      self.lastDetections = filteredResults
      return filteredResults
    } catch {
      print("Unexpected detection error: \(error).")
      return []
    }
  }

  /// Returns detections that have appeared (≈matched by IoU) in *N* consecutive frames.
  /// - Parameters:
  ///   - iouThreshold:  The intersection-over-union threshold that decides whether two boxes refer to the same object.
  ///   - stabilityPercent:  Minimum fraction of the currently buffered frames that a detection must continuously appear in to be considered *stable*.
  ///                        E.g. with a 6-frame buffer and `0.7`, a detection must persist for ≥5 consecutive frames.
  public func stableDetections(
    iouThreshold: CGFloat = 0.8,
    requiredConsecutiveFrames: Int = 4
  ) -> [VNRecognizedObjectObservation] {

    // Compute required consecutive frames (≥ 1).
    // Build a fresh stability map for **this** frame.
    var newStability: [CGRect: Int] = [:]
    var stableObservations: [VNRecognizedObjectObservation] = []

    for detection in lastDetections {
      var consecutive = 1  // At minimum it is present in the current frame.

      // Find any *previous* box that matches this one; if found, extend its streak.
      if let (prevKey, prevCount) = detectionStability.first(where: { (key, _) in
        detection.boundingBox.iou(with: key) > iouThreshold
      }) {
        consecutive = prevCount + 1
        // Remove so it won’t be matched again this iteration.
        detectionStability.removeValue(forKey: prevKey)
      }

      newStability[detection.boundingBox] = consecutive

      if consecutive >= requiredConsecutiveFrames {
        stableObservations.append(detection)
      }
    }

    // Replace map for next call.
    detectionStability = newStability

    return stableObservations
  }

  public func findBestCandidate(
    from detections: [VNRecognizedObjectObservation], target: CGRect
  ) -> VNRecognizedObjectObservation? {
    return detections.max(
      by: { $0.boundingBox.iou(with: target) < $1.boundingBox.iou(with: target) }
    )
  }
  public func changeInCenter(
    between first: CGRect, and second: CGRect
  ) -> Float {
    let distance = hypotf(
      Float(first.midX) - Float(second.midX), Float(first.midY) - Float(second.midY))
    return distance
  }

  public func changeInArea(
    between first: CGRect, and second: CGRect
  ) -> Float {
    let distance = Float(first.width * first.height) - Float(second.width * second.height)
    return sqrt(pow(distance, 2))
  }

}

 extension UIImage {
   func saveToPhotoLibrary(completion: @escaping (Bool, Error?) -> Void) {
     PHPhotoLibrary.requestAuthorization { status in
       guard status == .authorized else {
         completion(
           false,
           NSError(
             domain: "PhotoLibrary", code: 1,
             userInfo: [NSLocalizedDescriptionKey: "No permission to access photo library"]))
         return
       }

       PHPhotoLibrary.shared().performChanges(
         {
           PHAssetChangeRequest.creationRequestForAsset(from: self)
         }, completionHandler: completion)
     }
   }
 }
