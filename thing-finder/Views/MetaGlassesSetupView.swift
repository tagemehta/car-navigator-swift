// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

//
//  MetaGlassesSetupView.swift
//  thing-finder
//
//  Setup dialog flow for connecting Meta Ray-Ban glasses.
//  4-step flow: Pre-flight → Register → Camera Permission → Success.
//  Uses consolidated MetaGlassesViewModel (DAT SDK 0.7).
//

import SwiftUI

/// Setup step for the Meta glasses onboarding flow
enum MetaGlassesSetupStep: Int, CaseIterable {
  case preflight = 0
  case register = 1
  case cameraPermission = 2
  case success = 3
}

struct MetaGlassesSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var glassesVM: MetaGlassesViewModel
  @State private var currentStep: MetaGlassesSetupStep = .preflight

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        stepIndicator

        switch currentStep {
        case .preflight:
          preflightStep
        case .register:
          registerStep
        case .cameraPermission:
          cameraPermissionStep
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
        // Determine initial step based on current state
        switch glassesVM.state {
        case .ready, .streaming, .paused:
          currentStep = .success
        case .registered:
          currentStep = .cameraPermission
        case .registering:
          currentStep = .register
        default:
          break
        }
      }
      .onChange(of: glassesVM.state) { _, newState in
        switch newState {
        case .registered:
          currentStep = .cameraPermission
        case .ready, .streaming, .paused:
          currentStep = .success
        case .failed:
          break  // Stay on current step; error shown inline
        default:
          break
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
    // The dots are purely visual; expose a single spoken progress label instead.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Step \(currentStep.rawValue + 1) of \(MetaGlassesSetupStep.allCases.count)")
  }

  // MARK: - Step 1: Pre-flight Checklist

  private var preflightStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Before You Start")
        .font(.title2)
        .bold()

      Text("Make sure you've completed these steps in the Meta AI app:")
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 12) {
        instructionRow(number: 1, text: "Open the **Meta AI** app on your phone")
        instructionRow(number: 2, text: "Go to **Settings** → **Your glasses**")
        instructionRow(number: 3, text: "Enable **Developer Mode**")
        instructionRow(number: 4, text: "Ensure glasses are **open and powered on**")
      }
      .padding()
      .background(Color(.secondarySystemBackground))
      .cornerRadius(12)

      HStack {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
        Text("Developer Mode turns off after firmware updates — re-enable if needed.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Step 2: Register with Meta AI

  private var registerStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Register with Meta AI")
        .font(.title2)
        .bold()

      Text(
        "Register this app with the Meta AI companion app. You'll be briefly redirected to Meta AI to approve."
      )
      .foregroundColor(.secondary)

      VStack(spacing: 16) {
        if case .failed(let msg) = glassesVM.state {
          VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundColor(.orange)
              .accessibilityHidden(true)
            Text("Registration Error")
              .font(.headline)
              .accessibilityAddTraits(.isHeader)
            Text(msg)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)

            Button("Try Again") {
              glassesVM.resetFailure()
              glassesVM.connectGlasses()
            }
            .buttonStyle(.bordered)
          }
          .padding()
        } else if glassesVM.state == .registering {
          VStack(spacing: 12) {
            ProgressView()
              .scaleEffect(1.5)
              .accessibilityHidden(true)
            Text("Waiting for Meta AI...")
              .foregroundColor(.secondary)
            Text("Complete the registration in the Meta AI app, then return here.")
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding()
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            "Waiting for Meta AI. Complete the registration in the Meta AI app, then return here.")
        } else {
          Button {
            glassesVM.connectGlasses()
          } label: {
            HStack {
              Image(systemName: "link")
              Text("Register with Meta AI")
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
        Text("Ensure your glasses are open and connected via Bluetooth")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Step 3: Camera Permission

  private var cameraPermissionStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Grant Camera Access")
        .font(.title2)
        .bold()

      Text(
        "Now grant camera streaming permission so the app can receive video from your glasses."
      )
      .foregroundColor(.secondary)

      VStack(spacing: 16) {
        if case .failed(let msg) = glassesVM.state {
          VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.largeTitle)
              .foregroundColor(.orange)
              .accessibilityHidden(true)
            Text("Permission Error")
              .font(.headline)
              .accessibilityAddTraits(.isHeader)
            Text(msg)
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)

            Button("Try Again") {
              glassesVM.resetFailure()
              Task {
                await glassesVM.requestCameraPermission()
              }
            }
            .buttonStyle(.bordered)
          }
          .padding()
        } else if glassesVM.state == .requestingPermission {
          VStack(spacing: 12) {
            ProgressView()
              .scaleEffect(1.5)
              .accessibilityHidden(true)
            Text("Requesting camera permission...")
              .foregroundColor(.secondary)
            Text("Grant access in the Meta AI app when prompted.")
              .font(.caption)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding()
          .accessibilityElement(children: .combine)
          .accessibilityLabel(
            "Requesting camera permission. Grant access in the Meta AI app when prompted.")
        } else {
          Button {
            Task {
              await glassesVM.requestCameraPermission()
            }
          } label: {
            HStack {
              Image(systemName: "camera")
              Text("Grant Camera Permission")
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
        Image(systemName: "info.circle.fill")
          .foregroundColor(.blue)
        Text("You can choose \"Allow once\" or \"Allow always\" in Meta AI.")
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.top, 8)
    }
  }

  // MARK: - Step 4: Success

  private var successStep: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 80))
        .foregroundColor(.green)
        .accessibilityHidden(true)

      Text("All Set!")
        .font(.title)
        .bold()
        .accessibilityAddTraits(.isHeader)

      Text(
        "Your Meta Ray-Ban glasses are connected and camera access is granted. The app will now stream from your glasses."
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
      if currentStep != .preflight && currentStep != .success {
        Button("Back") {
          if let previous = MetaGlassesSetupStep(rawValue: currentStep.rawValue - 1) {
            currentStep = previous
          }
        }
        .buttonStyle(.bordered)
      }

      Spacer()

      switch currentStep {
      case .preflight:
        Button("I've Done This") {
          currentStep = .register
        }
        .buttonStyle(.borderedProminent)

      case .register, .cameraPermission:
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
        .accessibilityHidden(true)

      Text(LocalizedStringKey(text))
        .font(.subheadline)
    }
    // Read as one item, e.g. "Step 1: Open the Meta AI app".
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("Step \(number): ") + Text(LocalizedStringKey(text)))
  }
}

#Preview {
  MetaGlassesSetupView()
}
