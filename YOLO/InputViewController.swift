//
//  InputViewController.swift
//  YOLO
//
//  Created by Sam Mehta on 12/7/24.
//  Copyright © 2024 Ultralytics. All rights reserved.
//
import UIKit

class InputViewController: UIViewController {
  @IBOutlet weak var textField: UITextField!
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
  }

  override func viewDidAppear(_ animated: Bool) {
    textField.delegate = self
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
      if ModelConstants.modelValues.contains(modelLocal) {
        return (color: color, model: modelLocal, error: nil)
      } else {
        return (color: nil, model: nil, error: "We can't find that model of car")
      }
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
