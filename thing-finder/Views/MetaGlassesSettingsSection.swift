//
//  MetaGlassesSettingsSection.swift
//  thing-finder
//
//  Settings section for Meta Ray-Ban glasses configuration.
//

import SwiftUI

struct MetaGlassesSettingsSection: View {
  @ObservedObject var settings: Settings
  @StateObject private var manager = MetaGlassesManager.shared
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

        if manager.isRegistered || manager.hasEverRegistered {
          disconnectButton
        } else {
          connectButton
        }

        // Device count
        if !manager.availableDevices.isEmpty {
          Text("\(manager.availableDevices.count) device(s) available")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        #if DEBUG && canImport(MWDATMockDevice)
          // Mock device controls for testing
          Divider()
          Text("Testing (Debug Only)")
            .font(.caption)
            .foregroundColor(.secondary)

          if manager.hasMockDevice {
            Button("Remove Mock Device") {
              manager.removeMockDevice()
            }
            .foregroundColor(.orange)
          } else {
            Button("Add Mock Device") {
              manager.addMockDevice()
            }
            Text("Uses bundled video file for testing without glasses.")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        #endif

        // Error display
        if let error = manager.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundColor(.red)
        }
      }
    }
    .onChange(of: manager.shouldShowRegistrationSuccess) { _, shouldShow in
      if shouldShow {
        showingSuccessSheet = true
        manager.shouldShowRegistrationSuccess = false
      }
    }
    .sheet(isPresented: $showingSuccessSheet) {
      MetaGlassesSuccessView()
    }
  }

  // MARK: - Connection Status

  private var connectionStatusView: some View {
    HStack {
      Text("Status")
      Spacer()
      if manager.isRegistered || manager.hasEverRegistered {
        Label("Connected", systemImage: "checkmark.circle.fill")
          .foregroundColor(.green)
      } else {
        Label("Not Connected", systemImage: "xmark.circle")
          .foregroundColor(.secondary)
      }
    }
    .padding(.top, 4)
  }

  // MARK: - Buttons

  private var connectButton: some View {
    Button {
      showingSetupSheet = true
    } label: {
      HStack {
        Image(systemName: "eyeglasses")
        Text("Connect Glasses")
      }
    }
    .sheet(isPresented: $showingSetupSheet) {
      MetaGlassesSetupView()
    }
  }

  private var disconnectButton: some View {
    Button(role: .destructive) {
      manager.disconnectGlasses()
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
