import AVFoundation

class Speaker: SpeechOutput {
  private let synthesizer = AVSpeechSynthesizer()
  private let rate: Float
  public init(settings: Settings) {
    self.rate = Float(settings.speechRate)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handlePauseAllAudio),
      name: AudioControl.pauseAllNotification,
      object: nil
    )
  }
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
  public func speak(_ text: String) {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .word)  // Interrupt immediately
    }

    // Create an utterance with the text
    let utterance = AVSpeechUtterance(string: text)

    // Configure the utterance (optional)
    utterance.voice = AVSpeechSynthesisVoice(language: "en-US")  // Set the language
    utterance.rate = rate  // Speed of speech (0.0 to 1.0)
    utterance.pitchMultiplier = 1.0  // Pitch (0.5 to 2.0)

    // Speak the utterance
    synthesizer.speak(utterance)
  }

  @objc private func handlePauseAllAudio() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
  }
}
