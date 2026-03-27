//
//  MetaGlassesSuccessView.swift
//  thing-finder
//
//  Success modal shown after Meta glasses registration completes.
//

import SwiftUI

struct MetaGlassesSuccessView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Spacer()

        Image(systemName: "checkmark.circle.fill")
          .font(.largeTitle)
          .imageScale(.large)
          .foregroundColor(.green)

        Text("Connected!")
          .font(.title)
          .bold()

        Text(
          "Your Meta Ray-Ban glasses are now connected. The app will use the glasses camera when they are open and connected."
        )
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Image(systemName: "info.circle")
              .foregroundColor(.blue)
            Text("Important:")
              .bold()
          }
          Text("The glasses camera will only be used when:")
            .font(.caption)
            .foregroundColor(.secondary)
          Text("• Glasses are open (unfolded)")
            .font(.caption)
            .foregroundColor(.secondary)
          Text("• Glasses are connected via Bluetooth")
            .font(.caption)
            .foregroundColor(.secondary)
          Text("• Meta Glasses mode is enabled in Settings")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)

        Spacer()

        Button("Done") {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .padding(.bottom)
      }
      .padding()
      .navigationTitle("Meta Glasses")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

#Preview {
  MetaGlassesSuccessView()
}
