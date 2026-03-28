import AVFoundation

class Speaker: SpeechOutput {
  private let synthesizer = AVSpeechSynthesizer()
  private let settings: Settings

  public init(settings: Settings) {
    self.settings = settings
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

    // Configure the utterance with the user's chosen language
    let languageCode = settings.appLanguage.resolvedLanguageCode
    utterance.voice = AVSpeechSynthesisVoice(language: languageCode)

    // Compute rate dynamically from current settings
    let rate = Float(
      AVSpeechUtteranceMinimumSpeechRate + Float(settings.speechRate)
        * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate))
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
