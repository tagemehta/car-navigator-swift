//  Ultralytics YOLO 🚀 - AGPL-3.0 License
//
//  Main View Controller for Ultralytics YOLO App
//  This file is part of the Ultralytics YOLO app, enabling real-time object detection using YOLO11 models on iOS devices.
//  Licensed under AGPL-3.0. For commercial use, refer to Ultralytics licensing: https://ultralytics.com/license
//  Access the source code: https://github.com/ultralytics/yolo-ios-app
//
//  This ViewController manages the app's main screen, handling video capture, model selection, detection visualization,
//  and user interactions. It sets up and controls the video preview layer, handles model switching via a segmented control,
//  manages UI elements like sliders for confidence and IoU thresholds, and displays detection results on the video feed.
//  It leverages CoreML, Vision, and AVFoundation frameworks to perform real-time object detection and to interface with
//  the device's camera.

import AVFoundation
import CoreML
import CoreMedia
import UIKit
import Vision

var mlModel = try! yolo11n(configuration: .init()).model
//var classificationModel = try! carClassifier(configuration: .init()).model

class ViewController: UIViewController {
    @IBOutlet weak var info2: UILabel!
  @IBOutlet var videoPreview: UIView!
  @IBOutlet var View0: UIView!
  @IBOutlet var playButtonOutlet: UIBarButtonItem!
  @IBOutlet var pauseButtonOutlet: UIBarButtonItem!
  @IBOutlet weak var labelName: UILabel!
  @IBOutlet weak var labelFPS: UILabel!
  @IBOutlet weak var labelZoom: UILabel!
  @IBOutlet weak var labelVersion: UILabel!

  @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
  @IBOutlet weak var forcus: UIImageView!
  @IBOutlet weak var toolBar: UIToolbar!

  private var iou = 0.45
  private var conf = 0.8
  private var maxPred = 10
  private var isFound = false
  private var pastFrames: [[VNRecognizedObjectObservation]] = [[], [], [], [], []]
  private var sequenceRequestHandler = VNSequenceRequestHandler()
  private var detectedCar: Car?

  private var lastNavigatedBox: CGRect = CGRect.zero
  private var framesSinceNav = 0

  var filter: String?
  var carColorfilter: String = ""
  var carMakeModelfilter: String = ""
  private var currStreak: Int = 0
  private var gptCallInProgress: Bool = false
  private var carsCurrentlyInGPT: [Car] = []

  let selection = UISelectionFeedbackGenerator()
  var detector = try! VNCoreMLModel(for: mlModel)
  var session: AVCaptureSession!
  var videoCapture: VideoCapture!
  var currentBuffer: CVPixelBuffer?
  var framesDone = 0
  var t0 = 0.0  // inference start
  var t1 = 0.0  // inference dt
  var t2 = 0.0  // inference dt smoothed
  var t3 = CACurrentMediaTime()  // FPS start
  var t4 = 0.0  // FPS dt smoothed
  // var cameraOutput: AVCapturePhotoOutput!
  var longSide: CGFloat = 3
  var shortSide: CGFloat = 4
  var frameSizeCaptured = false

  // Developer mode
  let developerMode = UserDefaults.standard.bool(forKey: "developer_mode")  // developer mode selected in settings
  let save_detections = false  // write every detection to detections.txt
  let save_frames = false  // write every frame to frames.txt

    @IBAction func cancel(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func information2(_ sender: Any) {
        info2.text = "As you slowly scan your surroundings, we are checking each of the cars. Sometimes, the detections may take longer than others. You may hear, 'No cars found in this batch', which means that we don't think your Uber is on the screen."
        info2.isHidden.toggle()
    }
    
    // Text to Speech Helper
  let ttsHelper = TextToSpeechHelper()

  lazy var visionRequest: VNCoreMLRequest = {
    let request = VNCoreMLRequest(
      model: detector,
      completionHandler: {
        [weak self] request, error in
        self?.processObservations(for: request, error: error)
      })
    // NOTE: BoundingBoxView object scaling depends on request.imageCropAndScaleOption https://developer.apple.com/documentation/vision/vnimagecropandscaleoption
    request.imageCropAndScaleOption = .scaleFill  // .scaleFit, .scaleFill, .centerCrop
    return request
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    setLabels()
    setUpBoundingBoxViews()
    setUpOrientationChangeNotification()
    startVideo()
    ttsHelper.speak(text: "Searching for a " + carColorfilter + " " + carMakeModelfilter)
    // setModel()
  }

  override func viewWillTransition(
    to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    self.videoCapture.previewLayer?.frame = CGRect(
      x: 0, y: 0, width: size.width, height: size.height)

  }

  private func setUpOrientationChangeNotification() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(orientationDidChange),
      name: UIDevice.orientationDidChangeNotification, object: nil)
  }

  @objc func orientationDidChange() {
    videoCapture.updateVideoOrientation()
    //      frameSizeCaptured = false
  }

  @IBAction func takePhoto(_ sender: Any?) {
    let t0 = DispatchTime.now().uptimeNanoseconds

    // 1. captureSession and cameraOutput
    // session = videoCapture.captureSession  // session = AVCaptureSession()
    // session.sessionPreset = AVCaptureSession.Preset.photo
    // cameraOutput = AVCapturePhotoOutput()
    // cameraOutput.isHighResolutionCaptureEnabled = true
    // cameraOutput.isDualCameraDualPhotoDeliveryEnabled = true
    // print("1 Done: ", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1E9)

    // 2. Settings
    let settings = AVCapturePhotoSettings()
    // settings.flashMode = .off
    // settings.isHighResolutionPhotoEnabled = cameraOutput.isHighResolutionCaptureEnabled
    // settings.isDualCameraDualPhotoDeliveryEnabled = self.videoCapture.cameraOutput.isDualCameraDualPhotoDeliveryEnabled

    // 3. Capture Photo
    usleep(20_000)  // short 10 ms delay to allow camera to focus
    self.videoCapture.cameraOutput.capturePhoto(
      with: settings, delegate: self as AVCapturePhotoCaptureDelegate)
    print("3 Done: ", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1E9)
  }

  func setLabels() {
    self.labelName.text = "Searching..."
    self.labelVersion.text = "Version " + UserDefaults.standard.string(forKey: "app_version")!
  }

  @IBAction func playButton(_ sender: Any) {
    selection.selectionChanged()
    self.videoCapture.start()
    playButtonOutlet.isEnabled = false
    pauseButtonOutlet.isEnabled = true
  }

  @IBAction func pauseButton(_ sender: Any?) {
    selection.selectionChanged()
    self.videoCapture.stop()
    playButtonOutlet.isEnabled = true
    pauseButtonOutlet.isEnabled = false
  }

  @IBAction func switchCameraTapped(_ sender: Any) {
    self.videoCapture.captureSession.beginConfiguration()
    let currentInput = self.videoCapture.captureSession.inputs.first as? AVCaptureDeviceInput
    self.videoCapture.captureSession.removeInput(currentInput!)
    // let newCameraDevice = currentInput?.device == .builtInWideAngleCamera ? getCamera(with: .front) : getCamera(with: .back)

    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
    guard let videoInput1 = try? AVCaptureDeviceInput(device: device) else {
      return
    }

    self.videoCapture.captureSession.addInput(videoInput1)
    self.videoCapture.captureSession.commitConfiguration()
  }

  // share image
  @IBAction func shareButton(_ sender: Any) {
    selection.selectionChanged()
    let settings = AVCapturePhotoSettings()
    self.videoCapture.cameraOutput.capturePhoto(
      with: settings, delegate: self as AVCapturePhotoCaptureDelegate)
  }

  // share screenshot
  @IBAction func saveScreenshotButton(_ shouldSave: Bool = true) {
    // let layer = UIApplication.shared.keyWindow!.layer
    // let scale = UIScreen.main.scale
    // UIGraphicsBeginImageContextWithOptions(layer.frame.size, false, scale);
    // layer.render(in: UIGraphicsGetCurrentContext()!)
    // let screenshot = UIGraphicsGetImageFromCurrentImageContext()
    // UIGraphicsEndImageContext()

    // let screenshot = UIApplication.shared.screenShot
    // UIImageWriteToSavedPhotosAlbum(screenshot!, nil, nil, nil)
  }

  let maxBoundingBoxViews = 100
  var boundingBoxViews = [BoundingBoxView]()
  var colors: [String: UIColor] = [:]
  let ultralyticsColorsolors: [UIColor] = [
    UIColor(red: 4 / 255, green: 42 / 255, blue: 255 / 255, alpha: 0.6),  // #042AFF
    UIColor(red: 11 / 255, green: 219 / 255, blue: 235 / 255, alpha: 0.6),  // #0BDBEB
    UIColor(red: 243 / 255, green: 243 / 255, blue: 243 / 255, alpha: 0.6),  // #F3F3F3
    UIColor(red: 0 / 255, green: 223 / 255, blue: 183 / 255, alpha: 0.6),  // #00DFB7
    UIColor(red: 17 / 255, green: 31 / 255, blue: 104 / 255, alpha: 0.6),  // #111F68
    UIColor(red: 255 / 255, green: 111 / 255, blue: 221 / 255, alpha: 0.6),  // #FF6FDD
    UIColor(red: 255 / 255, green: 68 / 255, blue: 79 / 255, alpha: 0.6),  // #FF444F
    UIColor(red: 204 / 255, green: 237 / 255, blue: 0 / 255, alpha: 0.6),  // #CCED00
    UIColor(red: 0 / 255, green: 243 / 255, blue: 68 / 255, alpha: 0.6),  // #00F344
    UIColor(red: 189 / 255, green: 0 / 255, blue: 255 / 255, alpha: 0.6),  // #BD00FF
    UIColor(red: 0 / 255, green: 180 / 255, blue: 255 / 255, alpha: 0.6),  // #00B4FF
    UIColor(red: 221 / 255, green: 0 / 255, blue: 186 / 255, alpha: 0.6),  // #DD00BA
    UIColor(red: 0 / 255, green: 255 / 255, blue: 255 / 255, alpha: 0.6),  // #00FFFF
    UIColor(red: 38 / 255, green: 192 / 255, blue: 0 / 255, alpha: 0.6),  // #26C000
    UIColor(red: 1 / 255, green: 255 / 255, blue: 179 / 255, alpha: 0.6),  // #01FFB3
    UIColor(red: 125 / 255, green: 36 / 255, blue: 255 / 255, alpha: 0.6),  // #7D24FF
    UIColor(red: 123 / 255, green: 0 / 255, blue: 104 / 255, alpha: 0.6),  // #7B0068
    UIColor(red: 255 / 255, green: 27 / 255, blue: 108 / 255, alpha: 0.6),  // #FF1B6C
    UIColor(red: 252 / 255, green: 109 / 255, blue: 47 / 255, alpha: 0.6),  // #FC6D2F
    UIColor(red: 162 / 255, green: 255 / 255, blue: 11 / 255, alpha: 0.6),  // #A2FF0B
  ]

  func setUpBoundingBoxViews() {
    // Ensure all bounding box views are initialized up to the maximum allowed.
    while boundingBoxViews.count < maxBoundingBoxViews {
      boundingBoxViews.append(BoundingBoxView())
    }

    // Retrieve class labels directly from the CoreML model's class labels, if available.
    guard let classLabels = mlModel.modelDescription.classLabels as? [String] else {
      fatalError("Class labels are missing from the model description")
    }

    // Assign random colors to the classes.
    var count = 0
    for label in classLabels {
      let color = ultralyticsColorsolors[count]
      count += 1
      if count > 19 {
        count = 0
      }
      colors[label] = color

    }
  }

  func startVideo() {
    videoCapture = VideoCapture()
    videoCapture.delegate = self

    videoCapture.setUp(sessionPreset: .photo) { success in
      // .hd4K3840x2160 or .photo (4032x3024)  Warning: 4k may not work on all devices i.e. 2019 iPod
      if success {
        // Add the video preview into the UI.
        if let previewLayer = self.videoCapture.previewLayer {
          self.videoPreview.layer.addSublayer(previewLayer)
          self.videoCapture.previewLayer?.frame = self.videoPreview.bounds  // resize preview layer
        }

        // Add the bounding box layers to the UI, on top of the video preview.
        for box in self.boundingBoxViews {
          box.addToLayer(self.videoPreview.layer)
        }

        // Once everything is set up, we can start capturing live video.
        self.videoCapture.start()
      }
    }
  }

  func detectCars(sampleBuffer: CMSampleBuffer) -> [VNRecognizedObjectObservation] {
    if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      currentBuffer = pixelBuffer
      if !frameSizeCaptured {
        let frameWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let frameHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        longSide = max(frameWidth, frameHeight)
        shortSide = min(frameWidth, frameHeight)
        frameSizeCaptured = true
      }
      /// - Tag: MappingOrientation
      // The frame is always oriented based on the camera sensor,
      // so in most cases Vision needs to rotate it for the model to work as expected.
      let imageOrientation: CGImagePropertyOrientation
      switch UIDevice.current.orientation {
      case .portrait:
        imageOrientation = .up
      case .portraitUpsideDown:
        imageOrientation = .down
      case .landscapeLeft:
        imageOrientation = .up
      case .landscapeRight:
        imageOrientation = .up
      case .unknown:
        imageOrientation = .up
      default:
        imageOrientation = .up
      }

      // Invoke a VNRequestHandler with that image
      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
      if UIDevice.current.orientation != .faceUp {  // stop if placed down on a table
        t0 = CACurrentMediaTime()  // inference start
        do {
          try handler.perform([visionRequest])
          // Car objects bounding boxes
          if let results = visionRequest.results as? [VNRecognizedObjectObservation] {
            return results

          }
        } catch {
          print(error)
          return []
        }
        t1 = CACurrentMediaTime() - t0  // inference dt
      }

      currentBuffer = nil
    }
    return []
  }
  // Classifying by color and making gpt request
  func cropStableDetectionsFromBuffer(
    observations: [VNRecognizedObjectObservation], pixelBuffer: CMSampleBuffer
  ) -> [Car] {
    let pixelBuffer = CMSampleBufferGetImageBuffer(pixelBuffer)!
    let validCOCOObjects = ["bicycle", "car", "motorcycle", "bus", "truck"]
    var stableDetections: [Car] = []
      for observation in observations {
          let observation_class = observation.labels[0].identifier
          if validCOCOObjects.contains(observation_class) {
              let ogWidth = CGFloat(CVPixelBufferGetWidth(self.currentBuffer!))
              let ogHeight = CGFloat(CVPixelBufferGetHeight(self.currentBuffer!))
              
              let imageRect = self.normalizedRectToImageRect(
                normalizedRect: observation.boundingBox, originalWidth: ogWidth, originalHeight: ogHeight,
                modelWidth: 384, modelHeight: 640)  // Hard coded values here
              let ciImage = CIImage(cvImageBuffer: pixelBuffer).cropped(to: imageRect)
              let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!
              var framesAppearedIn = 0  // Frames where the bounding box has an intersection
              for pastFrame in pastFrames {
                  for obj in pastFrame {  // For each detection in the old frame
                      let iou = self.intersectionOverUnion(
                        rect1: observation.boundingBox, rect2: obj.boundingBox)
                      if iou > 0.8 {
                          framesAppearedIn += 1
                          break
                      }
                  }
              }
              if framesAppearedIn > 4 {
                  stableDetections.append(Car(image: cgImage, observation: observation))
              }
      }
    }
    return stableDetections
  }

  func processObservations(for request: VNRequest, error: Error?) {
    DispatchQueue.main.async {
      if let results = request.results as? [VNRecognizedObjectObservation] {
        self.show(predictions: results)
      } else {
        self.show(predictions: [])
      }

      // Measure FPS
      if self.t1 < 10.0 {  // valid dt
        self.t2 = self.t1 * 0.05 + self.t2 * 0.95  // smoothed inference time
      }
      self.t4 = (CACurrentMediaTime() - self.t3) * 0.05 + self.t4 * 0.95  // smoothed delivered FPS
      self.labelFPS.text = String(format: "%.1f FPS - %.1f ms", 1 / self.t4, self.t2 * 1000)  // t2 seconds to ms
      self.t3 = CACurrentMediaTime()
    }
  }

  func startNavigation(in pixelBuffer: CVImageBuffer) {
    let ciImage = CIImage(cvImageBuffer: pixelBuffer)
    let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!

    // Create a tracking request
      let trackingRequest = detectedCar?.trackingRequest
    currStreak = 0
    // Perform the request on the first frame
    do {
      try sequenceRequestHandler.perform([trackingRequest!], on: cgImage)
    } catch {
      print("Error initializing tracker: \(error)")
    }
  }

  func trackObject(in sampleBuffer: CMSampleBuffer) -> CGRect? {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      print("Failed to get image buffer")
      return nil
    }

    // Create a CIImage from the CVImageBuffer
    let ciImage = CIImage(cvImageBuffer: imageBuffer)

    // Create a CIContext (reuse this for better performance in repeated calls)
    let context = CIContext()

    // Render the CIImage into a CGImage
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      print("Failed to create CGImage")
      return nil
    }
      
      guard let trackingRequest = detectedCar?.trackingRequest else {
      print("Tracking request is nil")
      return nil
    }

    do {
      try sequenceRequestHandler.perform([trackingRequest], on: cgImage)

      // Retrieve the updated bounding box
      if let observation = trackingRequest.results?.first as? VNDetectedObjectObservation,
        trackingRequest.isLastFrame == false{
          
          // If confidence of the tracking is too small, then just set tracking request to nil and stop
          if observation.confidence < 0.5{
              detectedCar?.trackingRequest = nil
              return nil
          }
          
        trackingRequest.inputObservation = observation
        
        DispatchQueue.main.async {
            let rectNew = CGRect(
                x: observation.boundingBox.origin.x * self.videoPreview.bounds.width,
                y: (1 - observation.boundingBox.origin.y - observation.boundingBox.height) * self.videoPreview.bounds.height,
                width: observation.boundingBox.width * self.videoPreview.bounds.width,
                height: observation.boundingBox.height * self.videoPreview.bounds.height)
          self.boundingBoxViews[0].show(frame: rectNew, label: "Detected Car", color: .red, alpha: 0.5)
        }
        return observation.boundingBox
      }
    } catch {
      print("Error tracking object: \(error)")
    }

    return nil
  }
    
    
  // Save text file
  func saveText(text: String, file: String = "saved.txt") {
    if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
      let fileURL = dir.appendingPathComponent(file)

      // Writing
      do {  // Append to file if it exists
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle.seekToEndOfFile()
        fileHandle.write(text.data(using: .utf8)!)
        fileHandle.closeFile()
      } catch {  // Create new file and write
        do {
          try text.write(to: fileURL, atomically: false, encoding: .utf8)
        } catch {
          print("no file written")
        }
      }

      // Reading
      // do {let text2 = try String(contentsOf: fileURL, encoding: .utf8)} catch {/* error handling here */}
    }
  }

  // Save image file
  func saveImage() {
    let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    let fileURL = dir!.appendingPathComponent("saved.jpg")
    let image = UIImage(named: "carfinder.png")
    FileManager.default.createFile(
      atPath: fileURL.path, contents: image!.jpegData(compressionQuality: 0.5), attributes: nil)
  }

  // Return hard drive space (GB)
  func freeSpace() -> Double {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
    do {
      let values = try fileURL.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey
      ])
      return Double(values.volumeAvailableCapacityForImportantUsage!) / 1E9  // Bytes to GB
    } catch {
      print("Error retrieving storage capacity: \(error.localizedDescription)")
    }
    return 0
  }

  // Return RAM usage (GB)
  func memoryUsage() -> Double {
    var taskInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    if kerr == KERN_SUCCESS {
      return Double(taskInfo.resident_size) / 1E9  // Bytes to GB
    } else {
      return 0
    }
  }

  func normalizedRectToImageRect(
    normalizedRect: CGRect,
    originalWidth: CGFloat,
    originalHeight: CGFloat,
    modelWidth: CGFloat,
    modelHeight: CGFloat
  ) -> CGRect {

    // Vision's scaleFill might have scaled and cropped the original image
    // to fit modelWidth x modelHeight.

    // Compute the scale factor Vision applied.
    let scaleFactor = max(modelWidth / originalWidth, modelHeight / originalHeight)

    // Compute the scaled image dimensions (after Vision's scaling).
    let scaledWidth = originalWidth * scaleFactor
    let scaledHeight = originalHeight * scaleFactor

    // Vision center-crops the scaled image to fit model dimensions:
    let dx = (scaledWidth - modelWidth) / 2.0
    let dy = (scaledHeight - modelHeight) / 2.0

    // Convert normalized coordinates [0.0,1.0] to model coordinates
    var x = normalizedRect.origin.x * modelWidth
    var y = normalizedRect.origin.y * modelHeight
    var w = normalizedRect.size.width * modelWidth
    var h = normalizedRect.size.height * modelHeight

    // Adjust for the cropping offset
    x += dx
    y += dy

    // Convert back to original image coordinates by dividing by scaleFactor
    x /= scaleFactor
    y /= scaleFactor
    w /= scaleFactor
    h /= scaleFactor

    // Vision's bounding box (0,0) is bottom-left. Convert to a top-left origin system if needed.
    // If your original image or CGImage coordinates start from top-left, invert the y-axis:
    let topLeftY = originalHeight - y - h

    return CGRect(x: x, y: topLeftY, width: w, height: h)
  }

  func show(predictions: [VNRecognizedObjectObservation]) {
    var str = ""
    // date
    let date = Date()
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: date)
    let minutes = calendar.component(.minute, from: date)
    let seconds = calendar.component(.second, from: date)
    let nanoseconds = calendar.component(.nanosecond, from: date)
    let sec_day =
      Double(hour) * 3600.0 + Double(minutes) * 60.0 + Double(seconds) + Double(nanoseconds) / 1E9  // seconds in the day

    let width = videoPreview.bounds.width  // 375 pix
    let height = videoPreview.bounds.height  // 812 pix

    if UIDevice.current.orientation == .portrait {

      // ratio = videoPreview AR divided by sessionPreset AR
      var ratio: CGFloat = 1.0
      if videoCapture.captureSession.sessionPreset == .photo {
        ratio = (height / width) / (4.0 / 3.0)  // .photo
      } else {
        ratio = (height / width) / (16.0 / 9.0)  // .hd4K3840x2160, .hd1920x1080, .hd1280x720 etc.
      }

      for i in 0..<boundingBoxViews.count {
          if isFound {
            boundingBoxViews[i].hide()
          }
          
        else if i < predictions.count && i < Int(maxPred) {
          let prediction = predictions[i]

          var rect = prediction.boundingBox  // normalized xywh, origin lower left
          switch UIDevice.current.orientation {
          case .portraitUpsideDown:
            rect = CGRect(
              x: 1.0 - rect.origin.x - rect.width,
              y: 1.0 - rect.origin.y - rect.height,
              width: rect.width,
              height: rect.height)
          case .landscapeLeft:
            rect = CGRect(
              x: rect.origin.x,
              y: rect.origin.y,
              width: rect.width,
              height: rect.height)
          case .landscapeRight:
            rect = CGRect(
              x: rect.origin.x,
              y: rect.origin.y,
              width: rect.width,
              height: rect.height)
          case .unknown:
            print("The device orientation is unknown, the predictions may be affected")
            fallthrough
          default: break
          }

          if ratio >= 1 {  // iPhone ratio = 1.218
            let offset = (1 - ratio) * (0.5 - rect.minX)
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: offset, y: -1)
            rect = rect.applying(transform)
            rect.size.width *= ratio
          } else {  // iPad ratio = 0.75
            let offset = (ratio - 1) * (0.5 - rect.maxY)
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: offset - 1)
            rect = rect.applying(transform)
            ratio = (height / width) / (3.0 / 4.0)
            rect.size.height /= ratio
          }

          // Scale normalized to pixels [375, 812] [width, height]
          rect = VNImageRectForNormalizedRect(rect, Int(width), Int(height))

          // The labels array is a list of VNClassificationObservation objects,
          // with the highest scoring class first in the list.
          let bestClass = prediction.labels[0].identifier
          let confidence = prediction.labels[0].confidence
          // print(confidence, rect)  // debug (confidence, xywh) with xywh origin top left (pixels)
          let label = String(format: "%@ %.1f", bestClass, confidence * 100)
          let alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
          // Show the bounding box.
          boundingBoxViews[i].show(
            frame: rect,
            label: label,
            color: colors[bestClass] ?? UIColor.white,
            alpha: alpha)  // alpha 0 (transparent) to 1 (opaque) for conf threshold 0.2 to 1.0)

          if developerMode {
            // Write
            if save_detections {
              str += String(
                format: "%.3f %.3f %.3f %@ %.2f %.1f %.1f %.1f %.1f\n",
                sec_day, freeSpace(), UIDevice.current.batteryLevel, bestClass, confidence,
                rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
            }
          }
        } else {
          boundingBoxViews[i].hide()
        }
      }
    } else {
      let frameAspectRatio = longSide / shortSide
      let viewAspectRatio = width / height
      var scaleX: CGFloat = 1.0
      var scaleY: CGFloat = 1.0
      var offsetX: CGFloat = 0.0
      var offsetY: CGFloat = 0.0

      if frameAspectRatio > viewAspectRatio {
        scaleY = height / shortSide
        scaleX = scaleY
        offsetX = (longSide * scaleX - width) / 2
      } else {
        scaleX = width / longSide
        scaleY = scaleX
        offsetY = (shortSide * scaleY - height) / 2
      }

      for i in 0..<boundingBoxViews.count {
        if i < predictions.count {
          let prediction = predictions[i]

          var rect = prediction.boundingBox

          rect.origin.x = rect.origin.x * longSide * scaleX - offsetX
          rect.origin.y =
            height
            - (rect.origin.y * shortSide * scaleY - offsetY + rect.size.height * shortSide * scaleY)
          rect.size.width *= longSide * scaleX
          rect.size.height *= shortSide * scaleY

          let bestClass = prediction.labels[0].identifier
          let confidence = prediction.labels[0].confidence

          let label = String(format: "%@ %.1f", bestClass, confidence * 100)
          let alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
          // Show the bounding box.
          boundingBoxViews[i].show(
            frame: rect,
            label: label,
            color: colors[bestClass] ?? UIColor.white,
            alpha: alpha)  // alpha 0 (transparent) to 1 (opaque) for conf threshold 0.2 to 1.0)
        } else {
          boundingBoxViews[i].hide()
        }
      }
    }
    // Write
    if developerMode {
      if save_detections {
        saveText(text: str, file: "detections.txt")  // Write stats for each detection
      }
      if save_frames {
        str = String(
          format: "%.3f %.3f %.3f %.3f %.1f %.1f %.1f\n",
          sec_day, freeSpace(), memoryUsage(), UIDevice.current.batteryLevel,
          self.t1 * 1000, self.t2 * 1000, 1 / self.t4)
        saveText(text: str, file: "frames.txt")  // Write stats for each image
      }
    }

    // Debug
    // print(str)
    // print(UIDevice.current.identifierForVendor!)
    // saveImage()
  }

  // Pinch to Zoom Start ---------------------------------------------------------------------------------------------
  let minimumZoom: CGFloat = 1.0
  let maximumZoom: CGFloat = 10.0
  var lastZoomFactor: CGFloat = 1.0

  @IBAction func pinch(_ pinch: UIPinchGestureRecognizer) {
    let device = videoCapture.captureDevice

    // Return zoom value between the minimum and maximum zoom values
    func minMaxZoom(_ factor: CGFloat) -> CGFloat {
      return min(min(max(factor, minimumZoom), maximumZoom), device.activeFormat.videoMaxZoomFactor)
    }

    func update(scale factor: CGFloat) {
      do {
        try device.lockForConfiguration()
        defer {
          device.unlockForConfiguration()
        }
        device.videoZoomFactor = factor
      } catch {
        print("\(error.localizedDescription)")
      }
    }

    let newScaleFactor = minMaxZoom(pinch.scale * lastZoomFactor)
    switch pinch.state {
    case .began, .changed:
      update(scale: newScaleFactor)
      self.labelZoom.text = String(format: "%.2fx", newScaleFactor)
      self.labelZoom.font = UIFont.preferredFont(forTextStyle: .title2)
    case .ended:
      lastZoomFactor = minMaxZoom(newScaleFactor)
      update(scale: lastZoomFactor)
      self.labelZoom.font = UIFont.preferredFont(forTextStyle: .body)
    default: break
    }
  }  // Pinch to Zoom End --------------------------------------------------------------------------------------------
}  // ViewController class End

extension ViewController: VideoCaptureDelegate {
  func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
      
    // Run the loop if the car has not been found yet
      
    if !isFound {
      // Call car detection to update list of cars that will be passed into GPT
      var results = detectCars(sampleBuffer: sampleBuffer)
      // Only care about the results that have a confidence above 50%
      results = results.filter { $0.confidence > 0.5 }
      if results.count > 0 {
        let stableDetections = self.cropStableDetectionsFromBuffer(
          observations: results, pixelBuffer: sampleBuffer)
        // Initialize tracking requests and make the GPT Call
          if stableDetections.count > 0 && !gptCallInProgress {
              self.gptCallInProgress = true
              self.carsCurrentlyInGPT = stableDetections
                            
              print("Creating tracking requests")
              
              // Make the tracking requests for all the cars that will be passed into GPT
              for car in self.carsCurrentlyInGPT {
                  // Create a VNDetectedObjectObservation from the car's bounding box
                  let detectedObjectObservation = VNDetectedObjectObservation(
                    boundingBox: car.detectionObservation.boundingBox)
                  
                  print("about to create the tracking request for " + car.id)
                  
                  // Create the tracking request with the observation and set the completion handler during initialization
                  car.trackingRequest = VNTrackObjectRequest(detectedObjectObservation: detectedObjectObservation) {
                      request, error in
                      
                      if let error = error {
                          print("Tracking error: \(error)")
                          return
                      }
                      
                      // Get the observation from the request results
                      guard let observation = request.results?.first as? VNDetectedObjectObservation else {
                          print("Invalid tracking observation")
                          return
                      }
                      
                      // Update the car's bounding box with the new tracking data
                      DispatchQueue.main.async {
                          car.trackingConfidence = observation.confidence
                          
                          // If confidence is too low, mark for potential removal
                          if observation.confidence < 0.3 {
                              car.isLostInTracking = true
                          }
                          
                          // Only update bounding box if car isn't lost
                          if !car.isLostInTracking{
                              car.boundingBox = observation.boundingBox
                          }
                      }
                  }
                  
                  // Configure the tracking request (optional settings)
                  car.trackingRequest?.trackingLevel = .accurate
                  car.trackingRequest?.isLastFrame = false
              }
              
              print("Done creating tracking requests!")
//              self.ttsHelper.speak(text: "Hold still")
              
              // After creating tracking requests, make call to GPT
              // Use Task to handle the async work without blocking
              Task {
                  // First, capture any values we need from self to avoid strong reference cycles
                  let carDescription = self.carMakeModelfilter
                  
                  // Process the cars asynchronously
                  print("About to make the GPT Call!")
                  let results = await self.sendCarsToGPT(
                    cars: stableDetections, carDescription: carDescription)
                  // Switch to the main thread for UI updates
                  await MainActor.run {
                      // Process the structured results
                      var matchedCars: [Car] = []
                      
                      for result in results {
                          if result.isMatch{
                              if !result.car.isLostInTracking{
                                  // Add the matched car to our list
                                  matchedCars.append(result.car)
                                  print("Car matched with confidence: \(result.confidence)")
                              } else {
                                  let boundingBox = result.car.boundingBox // include confidence
                                  let midPoint = (boundingBox.midX, boundingBox.midY)
                                  if midPoint.0 < 0.4 {
                                      ttsHelper.speak(text: "Car was found but lost in tracking. It was last seen on the left side of your screen.")
                                  } else if midPoint.0 > 0.6 {
                                      ttsHelper.speak(text: "Car was found but lost in tracking. It was last seen on the right side of your screen.")
                                  } else {
                                      ttsHelper.speak(text: "Car was found but lost in tracking.")
                                  }
                              }
                          }
                      }
                      
                      // Notify the user if we found a match
                      if matchedCars.count > 0 && !self.isFound {
                          // If we want to track the first matched car
                          if let firstMatch = matchedCars.first, let currentBuffer = currentBuffer {
                              print("We have found the car!")
                              self.isFound = true

                              detectedCar = firstMatch
                              self.startNavigation(in: currentBuffer)
                          }
                      } else if matchedCars.isEmpty && !self.isFound{
                          self.ttsHelper.speak(text: "No matching cars found in this batch")
                      }
                      
                      // Reset the GPT call flag
                      self.gptCallInProgress = false
                      
                      // Get rid of all of the trackers for the cars currently in gpt
                      for car in self.carsCurrentlyInGPT{
                          if car.id != detectedCar?.id{
                              car.trackingRequest = nil
                              car.isLostInTracking = false
                              car.boundingBox = CGRect()
                          }
                      }
                      self.carsCurrentlyInGPT = []
                      
                      // If no matches were found, provide feedback
//                      if matchedCars.isEmpty && !self.isFound {
//                          self.ttsHelper.speak(text: "No matching cars found in this batch")
//                      }
                      
                  } // End of mainactor.run
                  
                  print("GPT response received")
              } // End of Task bracket
          }
        }

        // Update the past frames for the stable detections thing
        let _ = pastFrames.popLast()
        pastFrames.insert(results, at: 0)
        currentBuffer = nil
      }
      
      // Car has been found and now we need to track the car
      else {
        // Track the object every frame
        if let result = trackObject(in: sampleBuffer) {
          // Navigate once every 60 frames
          if framesSinceNav == 60 || framesSinceNav == 0 { // starts at 0 for first call, resets to 1 for calls after
              navigate(boundingBox: result)
          } else {
            framesSinceNav += 1
          }
        }
        
        // Object went out of frame, go back to detection mode
        else {
          isFound = false
          detectedCar = nil
          lastNavigatedBox = CGRect.zero
          framesSinceNav = 0
            self.ttsHelper.speak(text: "Lost car tracking, switching back to detection mode")
          print("Switching back")
       }
    }
  }
}

// Programmatically save image
extension ViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    if let error = error {
      print("error occurred : \(error.localizedDescription)")
    }
    if let dataImage = photo.fileDataRepresentation() {
      let dataProvider = CGDataProvider(data: dataImage as CFData)
      let cgImageRef: CGImage! = CGImage(
        jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
      var orientation = CGImagePropertyOrientation.right
      switch UIDevice.current.orientation {
      case .landscapeLeft:
        orientation = .up
      case .landscapeRight:
        orientation = .down
      default:
        break
      }
      var image = UIImage(cgImage: cgImageRef, scale: 0.5, orientation: .right)
      if let orientedCIImage = CIImage(image: image)?.oriented(orientation),
        let cgImage = CIContext().createCGImage(orientedCIImage, from: orientedCIImage.extent)
      {
        image = UIImage(cgImage: cgImage)
      }
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleAspectFill
      imageView.frame = videoPreview.frame
      let imageLayer = imageView.layer
      videoPreview.layer.insertSublayer(imageLayer, above: videoCapture.previewLayer)

      let bounds = UIScreen.main.bounds
      UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0.0)
      self.View0.drawHierarchy(in: bounds, afterScreenUpdates: true)
      let img = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      imageLayer.removeFromSuperlayer()
      let activityViewController = UIActivityViewController(
        activityItems: [img!], applicationActivities: nil)
      activityViewController.popoverPresentationController?.sourceView = self.View0
      self.present(activityViewController, animated: true, completion: nil)
      //
      //            // Save to camera roll
      //            UIImageWriteToSavedPhotosAlbum(img!, nil, nil, nil);
    } else {
      print("AVCapturePhotoCaptureDelegate Error")
    }
  }
}

extension ViewController {

    private func navigate(boundingBox: CGRect) {
      detectedCar?.boundingBox = boundingBox
    // let area = boundingBox.width * boundingBox.height
      let midPoint = (boundingBox.midX, boundingBox.midY)

    // Include midpoint calculation to see if bounding box is off the screen
        var pre = ""
        if framesSinceNav == 0 {
            pre = "We have found the car!. "
        }
        
      if midPoint.0 < 0.4 {
        ttsHelper.speak(text: "\(pre) Turn slightly left")
      } else if midPoint.0 > 0.6 {
        ttsHelper.speak(text: "\(pre) Turn slightly right")
      } else {
        ttsHelper.speak(text: "\(pre) Straight ahead")
      }
      lastNavigatedBox = boundingBox
      framesSinceNav = 1
  }
}
