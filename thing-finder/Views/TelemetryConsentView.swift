import SwiftUI

struct TelemetryConsentView: View {
  let onAccept: () -> Void
  let onDecline: () -> Void

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Text("Help Improve CurbToCar")
          .font(.title)
          .bold()
          .accessibilityAddTraits(.isHeader)

        Text(
          "We'd like to collect anonymous usage data to understand how well the app finds vehicles and where it falls short."
        )
        .font(.body)

        Text("What we collect:")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: 8) {
          BulletRow("Whether a vehicle was found and how long it took")
          BulletRow("Which verification steps succeeded or failed")
          BulletRow("Anonymous error counts per session")
        }

        Text("What we never collect:")
          .font(.headline)
          .accessibilityAddTraits(.isHeader)

        VStack(alignment: .leading, spacing: 8) {
          BulletRow("Images or video")
          BulletRow("Your location")
          BulletRow("License plate text")
          BulletRow("Any personally identifiable information")
        }

        Text("You can change this at any time in Settings.")
          .font(.caption)
          .foregroundColor(.secondary)

        Spacer()

        VStack(spacing: 12) {
          Button {
            onAccept()
          } label: {
            Text("Share Anonymous Data")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .accessibilityLabel("Share anonymous usage data")
          .accessibilityHint("Helps improve the app. No personal information is collected.")

          Button {
            onDecline()
          } label: {
            Text("No Thanks")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("No thanks, don't share data")
        }
      }
      .padding()
      .navigationBarTitleDisplayMode(.inline)
    }
    .interactiveDismissDisabled(true)
  }
}

private struct BulletRow: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text("•").accessibilityHidden(true)
      Text(text).font(.body)
    }
  }
}

#Preview {
    TelemetryConsentView(
        onAccept: {},
        onDecline: {}
    )
}

