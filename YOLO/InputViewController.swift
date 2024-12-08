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

    @IBAction func goToMainScreen(_ sender: UIButton) {
        performSegue(withIdentifier: "goToMain", sender: nil)
    }
    
    override func viewDidLoad() {
        textField.delegate = self
    }
    
    let colorMapping: [String: String] = [
        "White": "White",
        "Silver": "SilverGrey",
        "Grey": "SilverGrey",
        "Gray": "SilverGrey",
        "Black": "Black",
        "Brown": "Brown",
        "Red": "Red",
        "Maroon": "Red",
        "Orange": "Orange",
        "Yellow": "Yellow",
        "Gold": "Yellow",
        "Green": "Green",
        "Blue": "Blue",
        "Navy": "Blue",
        "Purple": "Purple",
        "Violet": "Purple"
    ]
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "goToMain" {
            if let destination = segue.destination as? ViewController {
                if let text = textField.text, !text.isEmpty {
                    if let result = parseCarDetails(text) {
                        destination.carColorfilter = colorMapping[result.color]!
                        destination.carMakeModelfilter = result.model
                    } else {
                        print("Invalid car details.")
                    }
                } else {
                    print("Text field is empty or nil.")
                }
            }
        }
    }
    
    func parseCarDetails(_ carDetails: String) -> (color: String, model: String)? {
        // Split the input string into words
        let words = carDetails.split(separator: " ")
        
        // Ensure there are at least two words (color and model)
        guard words.count > 1 else {
            return nil
        }
        
        // Extract the color (first word) and the model (remaining words)
        let color = String(words[0])
        let model = words[1...].joined(separator: " ")
        
        return (color, model)
    }
}

extension InputViewController: UITextFieldDelegate{
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
