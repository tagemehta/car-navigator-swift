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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "goToMain" {
            if let destination = segue.destination as? ViewController {
                destination.filter = textField.text
            }
        }
    }
}

