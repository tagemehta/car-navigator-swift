// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

//
//  MetaGlassesSettingsSection.swift
//  thing-finder
//
//  Settings section for Meta Ray-Ban glasses configuration.
//  Uses consolidated MetaGlassesViewModel (DAT SDK 0.7).
//

import MWDATCore
import SwiftUI

struct MetaGlassesSettingsSection: View {
  @ObservedObject var settings: Settings
  @EnvironmentObject private var glassesVM: MetaGlassesViewModel
  @State private var showingSetupSheet = false
  @State private var showingSuccessSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Use Meta Glasses Camera", isOn: $settings.useMetaGlasses)
      Text("Stream video from Meta Ray-Ban glasses instead of phone camera.")
        .font(.caption)
        .foregroundColor(.secondary)

      if settings.useMetaGlasses {
        connectionStatusView

        if glassesVM.isRegistered {
          disconnectButton
        } else {
          connectButton
        }

        // Device count
        if !glassesVM.availableDevices.isEmpty {
          Text("\(glassesVM.availableDevices.count) device(s) available")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        // Stream quality toggle
        Toggle("High Quality Stream", isOn: $settings.useHighQualityGlassesStream)
        Text("Uses more Bluetooth bandwidth for higher resolution (720p / 30fps).")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .onChange(of: glassesVM.shouldShowRegistrationSuccess) { _, shouldShow in
      if shouldShow {
        showingSuccessSheet = true
        glassesVM.shouldShowRegistrationSuccess = false
      }
    }
    .sheet(isPresented: $showingSuccessSheet) {
      MetaGlassesSuccessView()
    }
  }

  // MARK: - Connection Status

  private var connectionStatusView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
        Text(statusText)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      if let errorMsg = glassesVM.errorMessage {
        Text(errorMsg)
          .font(.caption)
          .foregroundColor(.red)
      }
    }
    .padding(.vertical, 4)
  }

  private var statusColor: Color {
    switch glassesVM.state {
    case .streaming:
      return .green
    case .ready, .paused:
      return .green.opacity(0.7)
    case .registered, .requestingPermission:
      return .orange
    case .registering:
      return .orange
    case .idle, .unconfigured:
      return .gray
    case .failed:
      return .red
    }
  }

  private var statusText: String {
    switch glassesVM.state {
    case .streaming:
      return "Streaming"
    case .ready:
      return "Connected — ready to stream"
    case .paused:
      return "Stream paused"
    case .registered:
      return "Registered — camera permission needed"
    case .requestingPermission:
      return "Requesting camera permission..."
    case .registering:
      return "Connecting to Meta AI..."
    case .idle:
      return "Available — not connected"
    case .unconfigured:
      return "Not available"
    case .failed:
      return "Error"
    }
  }

  // MARK: - Buttons

  private var connectButton: some View {
    Button {
      showingSetupSheet = true
    } label: {
      HStack {
        Image(systemName: "link")
        Text("Connect Glasses")
      }
    }
    .buttonStyle(.bordered)
    .sheet(isPresented: $showingSetupSheet) {
      MetaGlassesSetupView()
    }
  }

  private var disconnectButton: some View {
    Button(role: .destructive) {
      glassesVM.disconnectGlasses()
    } label: {
      HStack {
        Image(systemName: "xmark.circle")
        Text("Disconnect Glasses")
      }
    }
  }
}

#Preview {
  List {
    Section(header: Text("Meta Glasses")) {
      MetaGlassesSettingsSection(settings: Settings())
    }
  }
}
