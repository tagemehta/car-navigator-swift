// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

//
//  MetaGlassesSettingsSection.swift
//  thing-finder
//
//  Settings section for Meta Ray-Ban glasses configuration.
//  Uses consolidated MetaGlassesViewModel (DAT SDK 0.9).
//

import MWDATCore
import SwiftUI

struct MetaGlassesSettingsSection: View {
  @ObservedObject var settings: Settings
  @EnvironmentObject private var glassesVM: MetaGlassesViewModel
  @State private var showingSetupSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Use Meta Glasses Camera", isOn: $settings.useMetaGlasses)
      Text(toggleSubtext)
        .font(.caption)
        .foregroundColor(.secondary)

      if settings.useMetaGlasses {
        connectionStatusView

        checklistButton

        if glassesVM.isRegistered {
          disconnectButton
        }
      }
    }
    .sheet(isPresented: $showingSetupSheet) {
      MetaGlassesSetupView()
    }
    .onChange(of: glassesVM.shouldShowRegistrationSuccess) { _, shouldShow in
      // Registration success is surfaced in the setup checklist sheet;
      // consume the flag here to keep state clean without showing a
      // separate success modal on top of it.
      if shouldShow { glassesVM.shouldShowRegistrationSuccess = false }
    }
  }

  // MARK: - Toggle subtext

  /// Describes what action the user needs to take next, mirroring the
  /// first incomplete checklist step so settings and the sheet agree.
  private var toggleSubtext: String {
    guard settings.useMetaGlasses else {
      return "Stream video from Meta Ray-Ban glasses instead of phone camera."
    }
    if !glassesVM.isBluetoothOn { return "Turn on Bluetooth to use Meta glasses." }
    if !glassesVM.isRegistered { return "Connect to Meta AI to continue setup." }
    if glassesVM.availableDevices.isEmpty { return "Open and power on your glasses." }
    if !glassesVM.isDeviceConnected { return "Glasses found — open them to connect." }
    if !glassesVM.isCameraPermissionGranted { return "Grant camera access to start streaming." }
    return "Streaming from Meta Ray-Ban glasses."
  }

  // MARK: - Connection Status

  private var connectionStatusView: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
          .accessibilityHidden(true)
        Text(statusText)
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(statusText)

      if let errorMsg = glassesVM.errorMessage {
        Text(errorMsg)
          .font(.caption)
          .foregroundColor(.red)
      }
    }
    .padding(.vertical, 4)
  }

  /// Color reflects the first failing checklist step, not an internal SDK state.
  private var statusColor: Color {
    if !glassesVM.isBluetoothOn { return .red }
    if !glassesVM.isRegistered { return .orange }
    if glassesVM.availableDevices.isEmpty { return .orange }
    if !glassesVM.isDeviceConnected { return .orange }
    if !glassesVM.isCameraPermissionGranted { return .orange }
    switch glassesVM.state {
    case .streaming: return .green
    case .ready, .paused: return .green.opacity(0.7)
    default: return .gray
    }
  }

  /// Text mirrors the first incomplete checklist step so it's actionable.
  private var statusText: String {
    if !glassesVM.isBluetoothOn { return "Bluetooth is off" }
    if !glassesVM.isRegistered {
      return glassesVM.state == .registering ? "Connecting to Meta AI…" : "Not connected to Meta AI"
    }
    if glassesVM.availableDevices.isEmpty { return "No glasses found — open them to connect" }
    if !glassesVM.isDeviceConnected { return "Glasses not active — open them fully" }
    if !glassesVM.isCameraPermissionGranted {
      return glassesVM.state == .requestingPermission
        ? "Requesting camera access…" : "Camera access not granted"
    }
    switch glassesVM.state {
    case .streaming: return "Streaming"
    case .ready: return "Ready to stream"
    case .paused: return "Stream paused"
    default: return "Ready"
    }
  }

  // MARK: - Buttons

  private var checklistButton: some View {
    Button {
      showingSetupSheet = true
    } label: {
      HStack {
        Image(systemName: "checklist")
        Text("Connection Checklist")
      }
    }
    .buttonStyle(.bordered)
    .accessibilityHint("Opens the step-by-step glasses connection guide")
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
