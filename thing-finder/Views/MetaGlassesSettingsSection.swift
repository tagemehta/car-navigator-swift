//
//  MetaGlassesSettingsSection.swift
//  thing-finder
//
//  Settings section for Meta Ray-Ban glasses configuration.
//

import MWDATCore
import SwiftUI

struct MetaGlassesSettingsSection: View {
  @ObservedObject var settings: Settings
  @EnvironmentObject private var wearablesVM: WearablesViewModel
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

        if wearablesVM.registrationState == .registered {
          disconnectButton
        } else {
          connectButton
        }

        // Device count
        if !wearablesVM.devices.isEmpty {
          Text("\(wearablesVM.devices.count) device(s) available")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
    .onChange(of: wearablesVM.showGettingStartedSheet) { _, shouldShow in
      if shouldShow {
        showingSuccessSheet = true
        wearablesVM.showGettingStartedSheet = false
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

      if wearablesVM.showError {
        Text(wearablesVM.errorMessage)
          .font(.caption)
          .foregroundColor(.red)
      }
    }
    .padding(.vertical, 4)
  }

  private var statusColor: Color {
    switch wearablesVM.registrationState {
    case .registered:
      return .green
    case .registering:
      return .orange
    case .available, .unavailable:
      return .gray
    @unknown default:
      return .gray
    }
  }

  private var statusText: String {
    switch wearablesVM.registrationState {
    case .registered:
      return "Connected"
    case .registering:
      return "Connecting to Meta AI..."
    case .available:
      return "Available - not connected"
    case .unavailable:
      return "Not available"
    @unknown default:
      return "Unknown status"
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
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      MetaGlassesSuccessView()
        .onDisappear {
          wearablesVM.showGettingStartedSheet = false
        }
    }
  }

  private var disconnectButton: some View {
    Button(role: .destructive) {
      wearablesVM.disconnectGlasses()
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
