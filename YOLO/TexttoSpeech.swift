//
//  TextToSpeech.swift
//  YOLO
//
//  Created by Rushil Shah on 12/8/24.
//  Copyright © 2024 Ultralytics. All rights reserved.
//

import AVFoundation

class TextToSpeechHelper {
    private let synthesizer = AVSpeechSynthesizer()
    
    func speak(text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)  // Interrupt immediately
        }
        
        // Create an utterance with the text
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure the utterance (optional)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") // Set the language
        utterance.rate = 0.5 // Speed of speech (0.0 to 1.0)
        utterance.pitchMultiplier = 1.0 // Pitch (0.5 to 2.0)
        
        // Speak the utterance
        synthesizer.speak(utterance)
    }
}
