//
//  InputViewController.swift
//  YOLO
//
//  Created by Sam Mehta on 12/7/24.
//  Copyright © 2024 Ultralytics. All rights reserved.
//
import UIKit
import AVFoundation

class InputViewController: UIViewController {
  @IBOutlet weak var textField: UITextField!
  var videoCapture: VideoCapture!
  @IBOutlet weak var info1: UILabel!
  private let feedBackGenerator = UINotificationFeedbackGenerator()
  private var args: (color: String?, model: String?, error: String?) = (
    color: nil, model: nil, error: nil
  )
  private let ttsHelper = TextToSpeechHelper()
  private let colorMapping: [String: String] = [
    "white": "White",
    "silver": "SilverGrey",
    "grey": "SilverGrey",
    "gray": "SilverGrey",
    "black": "Black",
    "brown": "Brown",
    "red": "Red",
    "maroon": "Red",
    "orange": "Orange",
    "yellow": "Yellow",
    "gold": "Yellow",
    "green": "Green",
    "blue": "Blue",
    "navy": "Blue",
    "purple": "Purple",
    "violet": "Purple",
  ]
  @IBOutlet weak var warningText: UILabel!

  override func viewDidLoad() {
    textField.delegate = self
    feedBackGenerator.prepare()
    warningText.isHidden = true
      
      videoCapture = VideoCapture()
      // start camera session once
              videoCapture.setUp(sessionPreset: .photo) { [weak self] success in
                  guard let self = self, success else {
                      print("❌ Camera setup failed")
                      return
                  }
                  self.videoCapture.start()
              }
  }

    override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // stop the camera when leaving this screen
            videoCapture.stop()
        }
    
  override func viewDidAppear(_ animated: Bool) {
    textField.delegate = self
  }

    @IBAction func confirmCar(_ sender: Any){
        usleep(20_000)  // short 10 ms delay to allow camera to focus
        warningText.isHidden = true

        self.videoCapture.capturePhoto(delegate: self)
    }
    
  override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
    var errorMsg = ""
    if let text = textField.text, !text.isEmpty {
      let newArgs = parseCarDetails(textField.text ?? "")
      if newArgs.error == nil {
        args = newArgs
        feedBackGenerator.notificationOccurred(.success)
        warningText.isHidden = true
        return true
      } else {
        errorMsg = newArgs.error!
        warningText.text = errorMsg
      }
    } else {
      errorMsg = "Please enter a description of the car"
      warningText.text = errorMsg
    }
    warningText.isHidden = false
    ttsHelper.speak(text: errorMsg)
    feedBackGenerator.notificationOccurred(.error)
    return false
  }
    
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if let destination = segue.destination as? ViewController {
      destination.carColorfilter = args.color!
      destination.carMakeModelfilter = args.model!
      print(args)
    }
  }

    @IBAction func information1(_ sender: Any) {
        info1.text = "Copy and paste the color make model of your Uber and then click submit! Some buttons you will see on the next screen include 'Cancel' (on the top left), which will take you back to this screen, 'Confirm' (on the top right), which will send a picture of your current screen to ChatGPT to confirm that the car is correct, and another 'Information' button (on the bottom)."
        info1.isHidden.toggle()
    }
    func parseCarDetails(_ carDetails: String) -> (color: String?, model: String?, error: String?) {
    // Split the input string into words
    let words = carDetails.split(separator: " ")

    // Ensure there are at least two words (color and model)
    guard words.count > 1 else {
      return (nil, nil, "Please enter your description in the form of color space model")
    }

    // Extract the color (first word) and the model (remaining words)
    let colorLocal = String(words[0])
    let modelLocal = words[1...].joined(separator: " ").lowercased()
    if let color = colorMapping[colorLocal.lowercased()] {
      return (color: color, model: modelLocal, error: nil)
    } else {
      return (color: nil, model: nil, error: "We don't know that color")
    }
  }
}

extension InputViewController: UITextFieldDelegate {
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
  }
}

extension InputViewController: AVCapturePhotoCaptureDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput,
                   didFinishProcessingPhoto photo: AVCapturePhoto,
                   error: Error?) {
    if let error = error {
      print("Error capturing photo: \(error.localizedDescription)")
      return
    }
    
    guard let imageData = photo.fileDataRepresentation(),
          let image = UIImage(data: imageData) else {
      print("Failed to process photo data.")
      return
    }
    
      Task{
          do{
              let result = try await self.sendImgToGPT(img: image)
              print(result)
              ttsHelper.speak(text: result)
          }
          catch{
              print("Error received when passing image into GPT")
          }
      }
  }
}
