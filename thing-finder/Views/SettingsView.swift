import SwiftUI

struct SettingsView: View {
  @ObservedObject var settings: Settings

  var body: some View {
    NavigationStack {
      List {
        // MARK: - Navigation Feedback
        Section(header: Text("Navigation Feedback")) {
          Toggle("Navigate Before Plate Match", isOn: $settings.allowPartialNavigation)
          Text("Start navigation before a license plate match is confirmed.")
            .font(.caption)
            .foregroundColor(.secondary)

          Toggle("Announce All Detected Cars", isOn: $settings.announceRejected)
          Text("Announce every detected car, not just the target.")
            .font(.caption)
            .foregroundColor(.secondary)

          Toggle("Audio Beeps", isOn: $settings.enableBeeps)
          Text("Enable or disable audio beeps for feedback.")
            .font(.caption)
            .foregroundColor(.secondary)
          //          Toggle("Speech Guidance", isOn: $settings.enableSpeech)
          //          Toggle("Haptic Feedback", isOn: $settings.enableHaptics)

          VStack(alignment: .leading) {
            Text("Speech Rate: \(String(format: "%.1f", settings.speechRate))")
            Text("Adjusts the speed of spoken directions.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.speechRate, in: -1...1, step: 0.1)
              .accessibilityLabel("Speech Rate")
          }
        }

        // MARK: - Direction Settings
        Section(header: Text("Direction Settings")) {
          VStack(alignment: .leading) {
            Text("Left Threshold: \(Int(settings.directionLeftThreshold * 100))%")
            Text("How far left the target must be before announcing 'left'.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.directionLeftThreshold, in: 0.1...0.4, step: 0.01)
              .accessibilityLabel("Left Threshold")
          }

          VStack(alignment: .leading) {
            Text("Right Threshold: \(Int(settings.directionRightThreshold * 100))%")
            Text("How far right the target must be before announcing 'right'.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.directionRightThreshold, in: 0.6...0.9, step: 0.01)
              .accessibilityLabel("Right Threshold")
          }

          VStack(alignment: .leading) {
            Text("Repeat Interval: \(String(format: "%.1f", settings.speechRepeatInterval))s")
            Text("How often the same direction is repeated.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.speechRepeatInterval, in: 1...10, step: 0.5)
              .accessibilityLabel("Repeat Interval")
          }

          // VStack(alignment: .leading) {
          //   Text("Change Interval: \(String(format: "%.1f", settings.speechChangeInterval))s")
          //   Slider(value: $settings.speechChangeInterval, in: 0.5...5, step: 0.5)
          //     .accessibilityLabel("Change Interval")
          // }

          VStack(alignment: .leading) {
            Text("Waiting Phrase Cooldown: \(Int(settings.waitingPhraseCooldown))s")
            Text("Minimum time before repeating 'waiting' phrases.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.waitingPhraseCooldown, in: 2...20, step: 1)
              .accessibilityLabel("Waiting Phrase Cooldown")
          }
        }

        // MARK: - Beep Settings
        Section(header: Text("Beep Settings")) {
          VStack(alignment: .leading) {
            Text("Min Interval: \(String(format: "%.2f", settings.beepIntervalMin))s")
            Text("Shortest time between beeps when target is centered.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.beepIntervalMin, in: 0.05...0.5, step: 0.01)
              .accessibilityLabel("Minimum Beep Interval")
          }

          VStack(alignment: .leading) {
            Text("Max Interval: \(String(format: "%.1f", settings.beepIntervalMax))s")
            Text("Longest time between beeps when target is at the edge.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.beepIntervalMax, in: 0.5...2.0, step: 0.1)
              .accessibilityLabel("Maximum Beep Interval")
          }

          VStack(alignment: .leading) {
            Text("Smoothing: \(String(format: "%.2f", settings.smoothingAlpha))")
            Text("Smooths out rapid changes in beep frequency.")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $settings.smoothingAlpha, in: 0.05...0.5, step: 0.05)
              .accessibilityLabel("Beep Smoothing")
          }

          // Picker("Volume Curve", selection: $settings.volumeCurve) {
          //   ForEach(VolumeCurve.allCases) { curve in
          //     Text(curve.rawValue).tag(curve)
          //   }
          // }
          // Text("Controls how volume changes with distance.")
          //   .font(.caption)
          //   .foregroundColor(.secondary)
        }

        /*
        // MARK: - Distance Settings
        Section(header: Text("Distance Feedback")) {
          Picker("Volume Curve", selection: $settings.volumeCurve) {
            ForEach(VolumeCurve.allCases) { curve in
              Text(curve.rawValue).tag(curve)
            }
          }

          VStack(alignment: .leading) {
            Text("Min Distance: \(String(format: "%.1f", settings.distanceMin))m")
            Slider(value: $settings.distanceMin, in: 0.1...1.0, step: 0.1)
              .accessibilityLabel("Minimum Distance")
          }

          VStack(alignment: .leading) {
            Text("Max Distance: \(String(format: "%.1f", settings.distanceMax))m")
            Slider(value: $settings.distanceMax, in: 1.0...20.0, step: 0.5)
              .accessibilityLabel("Maximum Distance")
          }

          VStack(alignment: .leading) {
            Text("Min Volume: \(Int(settings.volumeMin * 100))%")
            Slider(value: $settings.volumeMin, in: 0.0...0.5, step: 0.05)
              .accessibilityLabel("Minimum Volume")
          }
        } */

        // MARK: - Camera Settings
        //        Section(header: Text("Camera Mode")) {
        //          Toggle(isOn: $settings.useARMode) {
        //            VStack(alignment: .leading, spacing: 4) {
        //              Text(settings.useARMode ? "AR Mode" : "Default Mode")
        //
        //              if settings.hasLiDAR && settings.useARMode {
        //                Text(
        //                  "Recommended: Switch to default mode. Able to provide same functionality"
        //                )
        //                .font(.caption)
        //                .foregroundColor(.secondary)
        //              } else if !settings.useARMode {
        //                Text("Optional: Switch to AR Mode for depth estimation")
        //                  .font(.caption)
        //                  .foregroundColor(.secondary)
        //              }
        //            }
        //          }
        //
        //          if settings.useARMode {
        //            VStack(alignment: .leading, spacing: 4) {
        //              HStack(spacing: 4) {
        //                Image(systemName: "battery.25")
        //                Text("Note: AR mode uses more battery")
        //              }
        //              .font(.caption)
        //              .foregroundColor(.orange)
        //
        //              if settings.hasLiDAR {
        //                Text(
        //                  "LiDAR is available on this device. Default mode is recommended for most use cases."
        //                )
        //                .font(.caption2)
        //                .foregroundColor(.secondary)
        //              } else {
        //                Text("AR mode provides better distance estimation on devices without LiDAR.")
        //                  .font(.caption2)
        //                  .foregroundColor(.secondary)
        //              }
        //            }
        //            .padding(.top, 4)
        //          }
        //        }
        // MARK: - Advanced Settings (Developer Mode)
        // if settings.developerMode {
        //   Section(header: Text("Detection Settings")) {
        //     VStack(alignment: .leading) {
        //       Text("Confidence: \(String(format: "%.2f", settings.confidenceThreshold))")
        //       Slider(value: $settings.confidenceThreshold, in: 0.1...0.9, step: 0.05)
        //         .accessibilityLabel("Confidence Threshold")
        //     }

        //     VStack(alignment: .leading) {
        //       Text(
        //         "Verification Cooldown: \(String(format: "%.1f", settings.verificationCooldown))s")
        //       Slider(value: $settings.verificationCooldown, in: 0.5...10.0, step: 0.5)
        //         .accessibilityLabel("Verification Cooldown")
        //     }

        //     Stepper(
        //       "Target Lifetime: \(settings.targetLifetime) frames",
        //       value: $settings.targetLifetime,
        //       in: 100...2000,
        //       step: 100)

        //     Stepper(
        //       "Max Lost Frames: \(settings.maxLostFrames)",
        //       value: $settings.maxLostFrames,
        //       in: 1...10)
        //   }
        // }

        // MARK: - Developer Options
        Section(header: Text("Developer Options")) {
          Toggle("Debug Overlay", isOn: $settings.debugOverlayEnabled)
          Text("Show verification details and debug messages.")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        // MARK: - Reset Section
        Section {
          Button("Reset to Defaults") {
            resetToDefaults()
          }
          .foregroundColor(.red)
        }
      }
      .navigationTitle("Settings")
    }
  }
  private func resetToDefaults() {
    // Call the resetToDefaults method on the Settings class
    settings.resetToDefaults()
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView(settings: Settings())
  }
}
