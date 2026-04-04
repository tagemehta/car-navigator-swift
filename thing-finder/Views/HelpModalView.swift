import SwiftUI

struct HelpModalView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {

          // MARK: - Getting Started
          HelpSection(
            title: "Getting Started",
            icon: "play.circle.fill",
            iconColor: .blue
          ) {
            Text(
              .init(
                "1. **Enter Ride Details**: Provide your vehicle's description and license plate through dictation, typing or copy/paste."
                  + " The description should include the make, model and color of your vehicle, or as many of those things you that you know."
              )

            )
            Text(
              "For paratransit vehicles, you can provide a more general description, like bus number, colors, logos, vehicle type or size."
                + "Since paratransit mode relies fully on llms to verify your vehicle, it may be more unreliable"
            )
            Text(
              "2. **Point Camera**: Aim at the pickup area where vehicles arrive. Magic tap to pause/resume camera."
            )
            Text("3. **Follow Audio Cues**: Listen for directional guidance and announcements")
            Text(
              "4. **Locate Vehicle**: Audio beeps become faster as you center the car and haptics (if enabled) become faster as you get closer"
            )
          }

          Divider()

          // MARK: - Siri Shortcuts
          HelpSection(
            title: "Siri Shortcuts",
            icon: "mic.fill",
            iconColor: .purple
          ) {
            Text("Use Siri to quickly start finding your ride")
            Text("• **'Hey Siri, find my car with CurbToCar'**")
            Text("• **'Hey Siri, find my ride with CurbToCar'**")
            Text("• **'Hey Siri, CurbToCar search'**")
            Text("• **'Hey Siri, find my paratransit vehicle with CurbToCar'**")
            Text(
              "Then Siri will ask you to describe your vehicle, and automatically launch the camera"
            )
          }

          Divider()

          // MARK: - Navigation Feedback
          HelpSection(
            title: "Navigation Feedback",
            icon: "speaker.wave.3.fill",
            iconColor: .green
          ) {
            HelpItem(
              title: "Audio Beeps",
              description:
                "Directional beeps that increase in frequency as you get closer to your vehicle"
            )
            HelpItem(
              title: "Speech Guidance",
              description: "Spoken directions like 'left', 'right', 'straight ahead' to guide you"
            )
            HelpItem(
              title: "Haptic Feedback",
              description: "Vibration patterns that pulse faster when approaching your target"
            )
            HelpItem(
              title: "Navigate Before Plate Match",
              description: "Start receiving guidance before license plate is fully verified"
            )
            HelpItem(
              title: "Announce All Cars",
              description:
                "Announce every car that the app sees, not just the one you are looking for."
            )
          }

          Divider()

          // MARK: - Meta Glasses
          if FeatureFlags.metaGlassesEnabled {
            HelpSection(
              title: "Meta Ray-Ban Glasses",
              icon: "eyeglasses",
              iconColor: .purple
            ) {
              Text("Use your Meta Ray-Ban smart glasses for hands-free, first-person detection:")
              Text("• **Connect**: Tap 'Connect Glasses' to pair with Meta AI app")
              Text("• **Permissions**: Grant camera access when prompted")
              Text("• **Hands-Free**: Keep your phone in your pocket while glasses do the work")
            }

            Divider()
          }

          // MARK: - Settings Tips
          HelpSection(
            title: "Customization Tips",
            icon: "slider.horizontal.3",
            iconColor: .orange
          ) {
            HelpItem(
              title: "Speech Rate",
              description: "Adjust how fast announcements are spoken"
            )
            HelpItem(
              title: "Repeat Interval",
              description: "Control how often the same direction is repeated (1-10 seconds)"
            )
            HelpItem(
              title: "Beep Intervals",
              description: "Fine-tune minimum and maximum beep frequency for comfort"
            )
            HelpItem(
              title: "Announce Options",
              description:
                "Choose what information you want announced (all cars, retry messages, waiting status)"
            )
          }

          Divider()

          // MARK: - Troubleshooting
          HelpSection(
            title: "Troubleshooting",
            icon: "wrench.and.screwdriver.fill",
            iconColor: .red
          ) {
            HelpItem(
              title: "No vehicles detected",
              description:
                "Ensure good lighting and point camera at the pickup area."
            )
            HelpItem(
              title: "Audio not working",
              description: "Check that 'Speech Guidance' and 'Audio Beeps' are enabled in settings."
            )
          }

          Divider()

          // MARK: - Contact
          VStack(alignment: .leading, spacing: 8) {
            Label("Need More Help?", systemImage: "envelope.fill")
              .font(.headline)
              .foregroundColor(.blue)

            Text("Contact us at:")
              .font(.subheadline)
              .foregroundColor(.secondary)

            Text("assistivetech@mit.edu")
              .font(.subheadline)
              .foregroundColor(.blue)
          }
          .padding(.vertical, 8)
        }
        .padding()
      }
      .navigationTitle("Help")
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

// MARK: - Helper Components

struct HelpSection<Content: View>: View {
  let title: LocalizedStringKey
  let icon: String
  let iconColor: Color
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: icon)
        .font(.title3)
        .fontWeight(.semibold)
        .foregroundColor(iconColor)

      VStack(alignment: .leading, spacing: 8) {
        content
      }
      .font(.subheadline)
    }
  }
}

struct HelpItem: View {
  let title: LocalizedStringKey
  let description: LocalizedStringKey

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline)
        .bold()
      Text(description)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

// MARK: - Preview

struct HelpModalView_Previews: PreviewProvider {
  static var previews: some View {
    HelpModalView()
  }
}
