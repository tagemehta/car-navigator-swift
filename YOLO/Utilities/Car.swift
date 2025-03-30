import CoreMedia
import Vision

class Car {
  var image: CGImage
  var detectionObservation: VNRecognizedObjectObservation
  var trackingRequest: VNTrackObjectRequest?
    var trackingConfidence: Float
    var isLostInTracking: Bool
  var id: String
  var boundingBox: CGRect

  init(image: CGImage, observation: VNRecognizedObjectObservation) {
    self.image = image
    self.detectionObservation = observation
    self.id = UUID().uuidString
    self.boundingBox = CGRect()
      self.isLostInTracking = false
      self.trackingConfidence = 0
  }

}
