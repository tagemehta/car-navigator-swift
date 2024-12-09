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

var mlModel = try! carDetector(configuration: .init()).model
var classificationModel = try! carClassifier(configuration: .init()).model
let modelMapping = [
    "AM General Hummer SUV 2000": "AM General Hummer",
    "Acura RL Sedan 2012": "Acura RL",
    "Acura TL Sedan 2012": "Acura TL",
    "Acura TL Type-S 2008": "Acura TL Type-S",
    "Acura TSX Sedan 2012": "Acura TSX",
    "Acura Integra Type R 2001": "Acura Integra Type R",
    "Acura ZDX Hatchback 2012": "Acura ZDX",
    "Aston Martin V8 Vantage Convertible 2012": "Aston Martin V8 Vantage",
    "Aston Martin V8 Vantage Coupe 2012": "Aston Martin V8 Vantage",
    "Aston Martin Virage Convertible 2012": "Aston Martin Virage",
    "Aston Martin Virage Coupe 2012": "Aston Martin Virage",
    "Audi RS 4 Convertible 2008": "Audi RS 4",
    "Audi A5 Coupe 2012": "Audi A5",
    "Audi TTS Coupe 2012": "Audi TTS",
    "Audi R8 Coupe 2012": "Audi R8",
    "Audi V8 Sedan 1994": "Audi V8",
    "Audi 100 Sedan 1994": "Audi 100",
    "Audi 100 Wagon 1994": "Audi 100",
    "Audi TT Hatchback 2011": "Audi TT",
    "Audi S6 Sedan 2011": "Audi S6",
    "Audi S5 Convertible 2012": "Audi S5",
    "Audi S5 Coupe 2012": "Audi S5",
    "Audi S4 Sedan 2012": "Audi S4",
    "Audi S4 Sedan 2007": "Audi S4",
    "Audi TT RS Coupe 2012": "Audi TT RS",
    "BMW ActiveHybrid 5 Sedan 2012": "BMW ActiveHybrid 5",
    "BMW 1 Series Convertible 2012": "BMW 1 Series",
    "BMW 1 Series Coupe 2012": "BMW 1 Series",
    "BMW 3 Series Sedan 2012": "BMW 3 Series",
    "BMW 3 Series Wagon 2012": "BMW 3 Series",
    "BMW 6 Series Convertible 2007": "BMW 6 Series",
    "BMW X5 SUV 2007": "BMW X5",
    "BMW X6 SUV 2012": "BMW X6",
    "BMW M3 Coupe 2012": "BMW M3",
    "BMW M5 Sedan 2010": "BMW M5",
    "BMW M6 Convertible 2010": "BMW M6",
    "BMW X3 SUV 2012": "BMW X3",
    "BMW Z4 Convertible 2012": "BMW Z4",
    "Bentley Continental Supersports Conv. Convertible 2012": "Bentley Continental Supersports",
    "Bentley Arnage Sedan 2009": "Bentley Arnage",
    "Bentley Mulsanne Sedan 2011": "Bentley Mulsanne",
    "Bentley Continental GT Coupe 2012": "Bentley Continental GT",
    "Bentley Continental GT Coupe 2007": "Bentley Continental GT",
    "Bentley Continental Flying Spur Sedan 2007": "Bentley Continental Flying Spur",
    "Bugatti Veyron 16.4 Convertible 2009": "Bugatti Veyron",
    "Bugatti Veyron 16.4 Coupe 2009": "Bugatti Veyron",
    "Buick Regal GS 2012": "Buick Regal",
    "Buick Rainier SUV 2007": "Buick Rainier",
    "Buick Verano Sedan 2012": "Buick Verano",
    "Buick Enclave SUV 2012": "Buick Enclave",
    "Cadillac CTS-V Sedan 2012": "Cadillac CTS-V",
    "Cadillac SRX SUV 2012": "Cadillac SRX",
    "Cadillac Escalade EXT Crew Cab 2007": "Cadillac Escalade",
    "Chevrolet Silverado 1500 Hybrid Crew Cab 2012": "Chevrolet Silverado 1500 Hybrid",
    "Chevrolet Corvette Convertible 2012": "Chevrolet Corvette",
    "Chevrolet Corvette ZR1 2012": "Chevrolet Corvette ZR1",
    "Chevrolet Corvette Ron Fellows Edition Z06 2007": "Chevrolet Corvette Z06",
    "Chevrolet Traverse SUV 2012": "Chevrolet Traverse",
    "Chevrolet Camaro Convertible 2012": "Chevrolet Camaro",
    "Chevrolet HHR SS 2010": "Chevrolet HHR",
    "Chevrolet Impala Sedan 2007": "Chevrolet Impala",
    "Chevrolet Tahoe Hybrid SUV 2012": "Chevrolet Tahoe Hybrid",
    "Chevrolet Sonic Sedan 2012": "Chevrolet Sonic",
    "Chevrolet Express Cargo Van 2007": "Chevrolet Express",
    "Chevrolet Avalanche Crew Cab 2012": "Chevrolet Avalanche",
    "Chevrolet Cobalt SS 2010": "Chevrolet Cobalt",
    "Chevrolet Malibu Hybrid Sedan 2010": "Chevrolet Malibu Hybrid",
    "Chevrolet TrailBlazer SS 2009": "Chevrolet TrailBlazer",
    "Chevrolet Silverado 2500HD Regular Cab 2012": "Chevrolet Silverado 2500HD",
    "Chevrolet Silverado 1500 Classic Extended Cab 2007": "Chevrolet Silverado 1500",
    "Chevrolet Express Van 2007": "Chevrolet Express",
    "Chevrolet Monte Carlo Coupe 2007": "Chevrolet Monte Carlo",
    "Chevrolet Malibu Sedan 2007": "Chevrolet Malibu",
    "Chevrolet Silverado 1500 Extended Cab 2012": "Chevrolet Silverado 1500",
    "Chevrolet Silverado 1500 Regular Cab 2012": "Chevrolet Silverado 1500",
    "Chrysler Aspen SUV 2009": "Chrysler Aspen",
    "Chrysler Sebring Convertible 2010": "Chrysler Sebring",
    "Chrysler Town and Country Minivan 2012": "Chrysler Town and Country",
    "Chrysler 300 SRT-8 2010": "Chrysler 300",
    "Chrysler Crossfire Convertible 2008": "Chrysler Crossfire",
    "Chrysler PT Cruiser Convertible 2008": "Chrysler PT Cruiser",
    "Daewoo Nubira Wagon 2002": "Daewoo Nubira",
    "Dodge Caliber Wagon 2012": "Dodge Caliber",
    "Dodge Caliber Wagon 2007": "Dodge Caliber",
    "Dodge Caravan Minivan 1997": "Dodge Caravan",
    "Dodge Ram Pickup 3500 Crew Cab 2010": "Dodge Ram 3500",
    "Dodge Ram Pickup 3500 Quad Cab 2009": "Dodge Ram 3500",
    "Dodge Sprinter Cargo Van 2009": "Dodge Sprinter",
    "Dodge Journey SUV 2012": "Dodge Journey",
    "Dodge Dakota Crew Cab 2010": "Dodge Dakota",
    "Dodge Dakota Club Cab 2007": "Dodge Dakota",
    "Dodge Magnum Wagon 2008": "Dodge Magnum",
    "Dodge Challenger SRT8 2011": "Dodge Challenger",
    "Dodge Durango SUV 2012": "Dodge Durango",
    "Dodge Durango SUV 2007": "Dodge Durango",
    "Dodge Charger Sedan 2012": "Dodge Charger",
    "Dodge Charger SRT-8 2009": "Dodge Charger",
    "Eagle Talon Hatchback 1998": "Eagle Talon",
    "FIAT 500 Abarth 2012": "FIAT 500",
    "FIAT 500 Convertible 2012": "FIAT 500",
    "Ferrari FF Coupe 2012": "Ferrari FF",
    "Ferrari California Convertible 2012": "Ferrari California",
    "Ferrari 458 Italia Convertible 2012": "Ferrari 458 Italia",
    "Ferrari 458 Italia Coupe 2012": "Ferrari 458 Italia",
    "Fisker Karma Sedan 2012": "Fisker Karma",
    "Ford F-450 Super Duty Crew Cab 2012": "Ford F-450 Super Duty",
    "Ford Mustang Convertible 2007": "Ford Mustang",
    "Ford Freestar Minivan 2007": "Ford Freestar",
    "Ford Expedition EL SUV 2009": "Ford Expedition",
    "Ford Edge SUV 2012": "Ford Edge",
    "Ford Ranger SuperCab 2011": "Ford Ranger",
    "Ford GT Coupe 2006": "Ford GT",
    "Ford F-150 Regular Cab 2012": "Ford F-150",
    "Ford F-150 Regular Cab 2007": "Ford F-150",
    "Ford Focus Sedan 2007": "Ford Focus",
    "Ford E-Series Wagon Van 2012": "Ford E-Series Wagon",
    "Ford Fiesta Sedan 2012": "Ford Fiesta",
    "GMC Terrain SUV 2012": "GMC Terrain",
    "GMC Savana Van 2012": "GMC Savana",
    "GMC Yukon Hybrid SUV 2012": "GMC Yukon Hybrid",
    "GMC Acadia SUV 2012": "GMC Acadia",
    "GMC Canyon Extended Cab 2012": "GMC Canyon",
    "Geo Metro Convertible 1993": "Geo Metro",
    "HUMMER H3T Crew Cab 2010": "HUMMER H3T",
    "HUMMER H2 SUT Crew Cab 2009": "HUMMER H2 SUT",
    "Honda Odyssey Minivan 2012": "Honda Odyssey",
    "Honda Odyssey Minivan 2007": "Honda Odyssey",
    "Honda Accord Coupe 2012": "Honda Accord",
    "Honda Accord Sedan 2012": "Honda Accord",
    "Hyundai Veloster Hatchback 2012": "Hyundai Veloster",
    "Hyundai Santa Fe SUV 2012": "Hyundai Santa Fe",
    "Hyundai Tucson SUV 2012": "Hyundai Tucson",
    "Hyundai Veracruz SUV 2012": "Hyundai Veracruz",
    "Hyundai Sonata Hybrid Sedan 2012": "Hyundai Sonata Hybrid",
    "Hyundai Elantra Sedan 2007": "Hyundai Elantra",
    "Hyundai Accent Sedan 2012": "Hyundai Accent",
    "Hyundai Genesis Sedan 2012": "Hyundai Genesis",
    "Hyundai Sonata Sedan 2012": "Hyundai Sonata",
    "Hyundai Elantra Touring Hatchback 2012": "Hyundai Elantra Touring",
    "Hyundai Azera Sedan 2012": "Hyundai Azera",
    "Infiniti G Coupe IPL 2012": "Infiniti G IPL",
    "Infiniti QX56 SUV 2011": "Infiniti QX56",
    "Isuzu Ascender SUV 2008": "Isuzu Ascender",
    "Jaguar XK XKR 2012": "Jaguar XK",
    "Jeep Patriot SUV 2012": "Jeep Patriot",
    "Jeep Wrangler SUV 2012": "Jeep Wrangler",
    "Jeep Liberty SUV 2012": "Jeep Liberty",
    "Jeep Grand Cherokee SUV 2012": "Jeep Grand Cherokee",
    "Jeep Compass SUV 2012": "Jeep Compass",
    "Lamborghini Reventon Coupe 2008": "Lamborghini Reventon",
    "Lamborghini Aventador Coupe 2012": "Lamborghini Aventador",
    "Lamborghini Gallardo LP 570-4 Superleggera 2012": "Lamborghini Gallardo",
    "Lamborghini Diablo Coupe 2001": "Lamborghini Diablo",
    "Land Rover Range Rover SUV 2012": "Land Rover Range Rover",
    "Land Rover LR2 SUV 2012": "Land Rover LR2",
    "Lincoln Town Car Sedan 2011": "Lincoln Town Car",
    "MINI Cooper Roadster Convertible 2012": "MINI Cooper Roadster",
    "Maybach Landaulet Convertible 2012": "Maybach Landaulet",
    "Mazda Tribute SUV 2011": "Mazda Tribute",
    "McLaren MP4-12C Coupe 2012": "McLaren MP4-12C",
    "Mercedes-Benz 300-Class Convertible 1993": "Mercedes-Benz 300-Class",
    "Mercedes-Benz C-Class Sedan 2012": "Mercedes-Benz C-Class",
    "Mercedes-Benz SL-Class Coupe 2009": "Mercedes-Benz SL-Class",
    "Mercedes-Benz E-Class Sedan 2012": "Mercedes-Benz E-Class",
    "Mercedes-Benz S-Class Sedan 2012": "Mercedes-Benz S-Class",
    "Mercedes-Benz Sprinter Van 2012": "Mercedes-Benz Sprinter",
    "Mitsubishi Lancer Sedan 2012": "Mitsubishi Lancer",
    "Nissan Leaf Hatchback 2012": "Nissan Leaf",
    "Nissan NV Passenger Van 2012": "Nissan NV Passenger",
    "Nissan Juke Hatchback 2012": "Nissan Juke",
    "Nissan 240SX Coupe 1998": "Nissan 240SX",
    "Plymouth Neon Coupe 1999": "Plymouth Neon",
    "Porsche Panamera Sedan 2012": "Porsche Panamera",
    "Ram C/V Cargo Van Minivan 2012": "Ram C/V",
    "Rolls-Royce Phantom Drophead Coupe Convertible 2012": "Rolls-Royce Phantom Drophead",
    "Spyker C8 Convertible 2009": "Spyker C8",
    "Suzuki Aerio Sedan 2007": "Suzuki Aerio",
    "Suzuki Kizashi Sedan 2012": "Suzuki Kizashi",
    "Suzuki SX4 Hatchback 2012": "Suzuki SX4",
    "Suzuki SX4 Sedan 2012": "Suzuki SX4",
    "Suzuki SX4 Wagon 2008": "Suzuki SX4",
    "Tesla Model S Sedan 2012": "Tesla Model S",
    "Toyota Sequoia SUV 2012": "Toyota Sequoia",
    "Toyota Camry Sedan 2012": "Toyota Camry",
    "Toyota Corolla Sedan 2012": "Toyota Corolla",
    "Toyota 4Runner SUV 2012": "Toyota 4Runner",
    "Volkswagen Golf Hatchback 2012": "Volkswagen Golf",
    "Volvo C30 Hatchback 2012": "Volvo C30",
    "Volvo XC90 SUV 2007": "Volvo XC90",
]

class ViewController: UIViewController {
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
  private var pastFrames: [[VNRecognizedObjectObservation]] = [[],[],[],[],[]]
  private var sequenceRequestHandler = VNSequenceRequestHandler()
  private var trackingRequest: VNTrackObjectRequest?
    
  private var stepInTrackingSeq = 0
  private let trackingSeqSteps = ["horizontally orient", "vertically orient", "move forward"]
  private var lastNavigatedBox: CGRect = CGRect.zero
  private var framesSinceNav = 0
    
  var filter: String?
  var carColorfilter: String = ""
  var carMakeModelfilter: String = ""
  private var currStreak: Int = 0
    
  let selection = UISelectionFeedbackGenerator()
  var detector = try! VNCoreMLModel(for: mlModel)
  var classifier = try! VNCoreMLModel(for: classificationModel)
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
    lazy var classificationRequest: VNRequest = {
        let request = VNCoreMLRequest(model: classifier)
        request.imageCropAndScaleOption = .centerCrop
        
        return request
    }()

  override func viewDidLoad() {
    super.viewDidLoad()
    setLabels()
    setUpBoundingBoxViews()
    setUpOrientationChangeNotification()
    startVideo()
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

  func predict(sampleBuffer: CMSampleBuffer) {
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
            if let results = visionRequest.results as? [VNRecognizedObjectObservation] {
                
                if results.count > 0 {self.classifyObservations(observations: results, pixelBuffer: pixelBuffer)}
            }
        } catch {
          print(error)
        }
        t1 = CACurrentMediaTime() - t0  // inference dt
      }

      currentBuffer = nil
    }
  }
    
    func classifyObservations(observations: [VNRecognizedObjectObservation], pixelBuffer: CVImageBuffer) {
        
        for observation in observations {
            if observation.labels[0].identifier  == carColorfilter {
                let ogWidth = CGFloat(CVPixelBufferGetWidth(self.currentBuffer!))
                let ogHeight = CGFloat(CVPixelBufferGetHeight(self.currentBuffer!))
                
                let imageRect = self.normalizedRectToImageRect(normalizedRect: observation.boundingBox, originalWidth: ogWidth, originalHeight: ogHeight, modelWidth: 384, modelHeight: 640) // Hard coded values here
                let ciImage = CIImage(cvImageBuffer: pixelBuffer).cropped(to: imageRect)
                let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!
                let handler = VNImageRequestHandler(cgImage: cgImage as CGImage, orientation: .up)
                do {
                    try handler.perform([classificationRequest])
                }catch {
                    print("an error occurred")
                }
                guard let cObservations = classificationRequest.results as? [VNClassificationObservation] else {
                    // Image classifiers, like MobileNet, only produce classification observations.
                    // However, other Core ML model types can produce other observations.
                    // For example, a style transfer model produces `VNPixelBufferObservation` instances.
                    let res = classificationRequest.results
                    print("VNRequest produced the wrong result type: \(type(of: classificationRequest.results)).")
                    return
                }
                var maxConfidence: VNConfidence = 0
                var identifier: String = ""
                for cObservation in cObservations {
                    if maxConfidence < cObservation.confidence{
                        identifier = cObservation.identifier
                        maxConfidence = cObservation.confidence
                    }
                }
                print(identifier, maxConfidence)
                if modelMapping[identifier] == carMakeModelfilter {
//                if identifier == carMakeModelfilter {
                    var presentFrames = 0 // Frames where the bounding box has an intersection
                    for pastFrame in pastFrames {
                        for obj in pastFrame { // For each detection in the old frame
                            let iou = self.intersectionOverUnion(rect1: observation.boundingBox, rect2: obj.boundingBox)
                            if (iou > 0.8) {
                                presentFrames+=1
                                break
                            }
                        }
                    }
                    
                    if presentFrames > 4 {
                        isFound = true
                        ttsHelper.speak(text: "We have found the car!")
                        print("We ahve found the one")
                        let rectNew = CGRect(x: imageRect.origin.x/ogWidth, y: imageRect.origin.y/ogHeight, width: imageRect.size.width/ogWidth, height: imageRect.size.height/ogHeight)
                        initializeTracker(with: rectNew, in: pixelBuffer)
                        return
                    }
                    
                }
                if (!isFound) {
                    let _ = pastFrames.popLast()
                    pastFrames.insert(observations, at: 0)
                    
                }
            }
        }
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

    
    func initializeTracker(with boundingBox: CGRect, in pixelBuffer: CVImageBuffer) {
        let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)!
            // Create a VNDetectedObjectObservation
        let initialObservation = VNDetectedObjectObservation(boundingBox: boundingBox)

            // Create a tracking request
        trackingRequest = VNTrackObjectRequest(detectedObjectObservation: initialObservation)
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
        
            guard let trackingRequest = trackingRequest else {
                print("Tracking request is nil")
                return nil
            }
        
            do {
                try sequenceRequestHandler.perform([trackingRequest], on: cgImage)

                // Retrieve the updated bounding box
                if let observation = trackingRequest.results?.first as? VNDetectedObjectObservation, trackingRequest.isLastFrame == false {
                    trackingRequest.inputObservation = observation
                    let rectNew = CGRect(x: observation.boundingBox.origin.x*videoPreview.bounds.width, y: observation.boundingBox.origin.y*videoPreview.bounds.height, width: observation.boundingBox.width*videoPreview.bounds.width, height: observation.boundingBox.height*videoPreview.bounds.height)
                    DispatchQueue.main.async {
                        self.boundingBoxViews[0].show(frame: rectNew, label: "box", color: .red, alpha: 0.5)
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

        // Compute the scaled image dimensions (after Vision’s scaling).
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

        // Vision’s bounding box (0,0) is bottom-left. Convert to a top-left origin system if needed.
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
        if i < predictions.count && i < Int(maxPred) {
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
      if !isFound {
          predict(sampleBuffer: sampleBuffer)
      }
    else {
        
        if let result = trackObject(in: sampleBuffer) {
            if (framesSinceNav == 60) {
                navigate()
            }
            else {
                framesSinceNav+=1
            }
            
        } else { // Object went out of frame
            // Checking to see if tracking loses the object for a frame and can find it again. Commented out because it would track random things
//            if currStreak > 0{
//                isFound = false
//                print("Switching back")
//                currStreak = 0
//            }
//            else{
//               currStreak += 1
//            }
            isFound = false
            lastNavigatedBox = CGRect.zero
            framesSinceNav = 0
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
    
    private func navigate() {
        guard let trackingRequest = trackingRequest else {
            print("Tracking request is nil")
            return
        } // Unwrap trackingrequest
        
        if let observation = trackingRequest.results?.first as? VNDetectedObjectObservation, trackingRequest.isLastFrame == false {
            
            let area = observation.boundingBox.width*observation.boundingBox.height
            let midPoint = (observation.boundingBox.midX, observation.boundingBox.midY)
            
            
            if (midPoint.0 < 0.4) {
                ttsHelper.speak(text: "Turn slightly left")
            }
            else if midPoint.0 > 0.6 {
                ttsHelper.speak(text: "Turn slightly right")
            }
            else {
                ttsHelper.speak(text:"Straight ahead")
            }
            lastNavigatedBox = observation.boundingBox
            framesSinceNav = 0
        }
    }    
}
