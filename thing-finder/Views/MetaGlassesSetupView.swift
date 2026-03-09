//
//  MetaGlassesSetupView.swift
//  thing-finder
//
//  Setup dialog flow for connecting Meta Ray-Ban glasses.
//

import SwiftUI

/// Setup step for the Meta glasses onboarding flow
enum MetaGlassesSetupStep: Int, CaseIterable {
  case developerMode = 0
  case requestPermission = 1
  case success = 2
}

struct MetaGlassesSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var manager = MetaGlassesManager.shared
  @State private var currentStep: MetaGlassesSetupStep = .developerMode

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        stepIndicator

        switch currentStep {
        case .developerMode:
          developerModeStep
        case .requestPermission:
          requestPermissionStep
        case .success:
          successStep
        }

        Spacer()

        navigationButtons
      }
      .padding()
      .navigationTitle("Connect Meta Glasses")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
      .onAppear {
        print(
          "[MetaGlassesSetupView] onAppear - isRegistered: \(manager.isRegistered), hasEverRegistered: \(manager.hasEverRegistered), isRegistrationInProgress: \(manager.isRegistrationInProgress)"
        )

        // Determine initial step based on current state
        if manager.isRegistered || manager.hasEverRegistered {
          currentStep = .success
        } else if manager.isRegistrationInProgress {
          currentStep = .requestPermission
        }
        // Otherwise stay on developerMode (step 1)
      }
      .onChange(of: manager.isRegistered) { _, isRegistered in
        print("[MetaGlassesSetupView] isRegistered changed to: \(isRegistered)")
        if isRegistered {
          currentStep = .success
        }
      }
      .onChange(of: manager.hasEverRegistered) { _, hasEverRegistered in
        if hasEverRegistered {
          currentStep = .success
        }
      }
    }
  }

  // MARK: - Step Indicator

  private var stepIndicator: some View {
    HStack(spacing: 8) {
      ForEach(MetaGlassesSetupStep.allCases, id: \.rawValue) { step in
        Circle()
          .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
          .frame(width: 10, height: 10)
      }
    }
    .padding(.top)
  }

  // MARK: - Step 1: Developer Mode

  private var developerModeStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Step 1: Enable Developer Mode")
        .font(.title2)
        .bold()

      Text("Before connecting, you need to enable Developer Mode in the Meta AI app:")
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 12) {
        instructionRow(number: 1, text: "Open the **Meta AI** app on your phone")
        instructionRow(number: 2, text: "Go to **Settings** → **App Info**")
        instructionRow(number: 3, text: "Click on the app version 5 times")
        instructionRow(number: 4, text: "Developer options should now be available")
      }
      .padding()
      .background(Color(.secondarySystemBackground))
      .cornerRadius(12)

      HStack {
        Image(systemName: "info.circle.fill")
          .foregroundColor(.blue)
        Text("Make sure your glasses are open and powered on")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Step 2: Request Permission

  private var requestPermissionStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Step 2: Grant Camera Access")
        .font(.title2)
        .bold()

      Text(
        "Tap the button below to open Meta AI and grant camera streaming permission to this app."
      )
      .foregroundColor(.secondary)

      VStack(spacing: 16) {
        if let errorMessage = manager.errorMessage {
          VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundColor(.orange)
            Text("Connection Error")
              .font(.headline)
            Text(errorMessage)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)

            // Allow retry after error
            Button("Try Again") {
              manager.errorMessage = nil
              manager.connectGlasses()
            }
            .buttonStyle(.bordered)
          }
          .padding()
        } else if manager.isRegistrationInProgress {
          VStack(spacing: 12) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Waiting for permission...")
              .foregroundColor(.secondary)
            Text("Complete the setup in Meta AI app, then return here.")
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding()
        } else {
          Button {
            manager.connectGlasses()
          } label: {
            HStack {
              Image(systemName: "link")
              Text("Connect to Meta AI")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
          }
        }
      }
      .padding()
      .background(Color(.secondarySystemBackground))
      .cornerRadius(12)

      HStack {
        Image(systemName: "eyeglasses")
          .foregroundColor(.blue)
        Text("Ensure your glasses are open and on your head")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Step 3: Success

  private var successStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 80))
        .foregroundColor(.green)

      Text("Connected!")
        .font(.title)
        .bold()

      Text(
        "Your Meta Ray-Ban glasses are now connected. The app will use the glasses camera when they are open and connected."
      )
      .multilineTextAlignment(.center)
      .foregroundColor(.secondary)

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
    }
  }

  // MARK: - Navigation Buttons

  private var navigationButtons: some View {
    HStack {
      if currentStep != .developerMode && currentStep != .success {
        Button("Back") {
          if let previous = MetaGlassesSetupStep(rawValue: currentStep.rawValue - 1) {
            currentStep = previous
          }
        }
        .buttonStyle(.bordered)
      }

      Spacer()

      switch currentStep {
      case .developerMode:
        Button("Continue") {
          currentStep = .requestPermission
        }
        .buttonStyle(.borderedProminent)

      case .requestPermission:
        EmptyView()

      case .success:
        Button("Done") {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  // MARK: - Helper Views

  private func instructionRow(number: Int, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)")
        .font(.caption)
        .bold()
        .foregroundColor(.white)
        .frame(width: 20, height: 20)
        .background(Color.accentColor)
        .clipShape(Circle())

      Text(LocalizedStringKey(text))
        .font(.subheadline)
    }
  }
}

#Preview {
  MetaGlassesSetupView()
}
