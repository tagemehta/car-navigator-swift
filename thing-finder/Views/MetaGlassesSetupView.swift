// COMMENTED OUT FOR APP STORE SUBMISSION - Meta SDK requires Bluetooth permissions
// Uncomment this file when ready to use Meta glasses in production

//
//  MetaGlassesSetupView.swift
//  thing-finder
//
//  Connection checklist for Meta Ray-Ban glasses.
//  Five sequential checks:
//    1. Bluetooth on
//    2. App registered (shown as "device connected")
//    3. Devices available
//    4. Device active (connected link state)
//    5. Camera permission granted
//
//  Each row shows its status and, when blocked, an inline action button
//  so the user can resolve the problem without leaving the sheet.
//
//  Screen-reader design:
//  - Each row is a static accessibility element describing step number,
//    name, status, and hint — no visual-only information.
//  - Action buttons are separate focusable elements immediately after
//    their row so they can be independently activated.
//  - In-progress spinner has an explicit label.
//  - The error footer posts a live-region update so it auto-announces.
//  - Dividers are hidden from the accessibility tree.
//  - "Done" button appearance posts an announcement via
//    UIAccessibility.post so blind users know all steps passed.
//

import MWDATCore
import SwiftUI

// MARK: - Checklist Step Model

private enum ChecklistStep: Int, CaseIterable {
  case bluetooth = 0
  case registered = 1
  case devicesAvailable = 2
  case deviceActive = 3
  case cameraPermission = 4

  var title: String {
    switch self {
    case .bluetooth: return "Bluetooth is on"
    case .registered: return "Device connected"
    case .devicesAvailable: return "Glasses available"
    case .deviceActive: return "Glasses active"
    case .cameraPermission: return "Camera access granted"
    }
  }

  /// Short instruction shown as the row subtitle and read as the VoiceOver hint.
  var hint: String {
    switch self {
    case .bluetooth: return "Required for glasses communication"
    case .registered: return "App registered with Meta AI"
    case .devicesAvailable: return "Open and power on your glasses"
    case .deviceActive: return "Glasses are open and connected"
    case .cameraPermission: return "Streaming permission from Meta AI"
    }
  }

  var actionLabel: String {
    switch self {
    case .bluetooth: return "Open Settings"
    case .registered: return "Connect to Meta AI"
    case .devicesAvailable: return "Refresh"
    case .deviceActive: return "Retry"
    case .cameraPermission: return "Grant Camera Access"
    }
  }

  /// Read aloud by VoiceOver when focus moves to the action button.
  var actionHint: String {
    switch self {
    case .bluetooth: return "Opens the iOS Settings app"
    case .registered: return "Opens the Meta AI registration flow"
    case .devicesAvailable: return "Re-checks for paired glasses"
    case .deviceActive: return "Retries connecting to your glasses"
    case .cameraPermission: return "Requests camera streaming permission in Meta AI"
    }
  }
}

private enum StepStatus: Equatable {
  case passed
  case inProgress
  case failed
  case waiting  // Blocked by an earlier step
}

// MARK: - MetaGlassesSetupView

struct MetaGlassesSetupView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var glassesVM: MetaGlassesViewModel

  /// Tracks whether we've already posted the completion announcement
  /// so it fires exactly once when all steps first become complete.
  @State private var didAnnounceCompletion = false

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 0) {
        headerSection
        Divider()
          .accessibilityHidden(true)
        checklistSection
        Spacer()
        footerSection
      }
      .navigationTitle("Connect Meta Glasses")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .onChange(of: allPassed) { _, nowPassed in
        guard nowPassed, !didAnnounceCompletion else { return }
        didAnnounceCompletion = true
        UIAccessibility.post(
          notification: .announcement,
          argument: "All steps complete. Your glasses are ready to stream."
        )
      }
    }
  }

  // MARK: - Header

  private var headerSection: some View {
    Text("Complete each step to start streaming from your Ray-Ban Meta glasses.")
      .font(.subheadline)
      .foregroundColor(.secondary)
      .padding()
    // Not a heading — it's body copy. accessibilityAddTraits(.isHeader)
    // is reserved for section headings so the rotor remains meaningful.
  }

  // MARK: - Checklist

  private var checklistSection: some View {
    VStack(spacing: 0) {
      ForEach(ChecklistStep.allCases, id: \.rawValue) { step in
        let stepStatus = status(for: step)
        let stepNumber = step.rawValue + 1
        let total = ChecklistStep.allCases.count

        ChecklistRowView(
          step: step,
          stepNumber: stepNumber,
          totalSteps: total,
          status: stepStatus
        ) {
          performAction(for: step)
        }

        if step != ChecklistStep.allCases.last {
          Divider()
            .padding(.leading, 56)
            .accessibilityHidden(true)
        }
      }
    }
    .padding(.vertical, 8)
  }

  // MARK: - Footer

  private var footerSection: some View {
    VStack(spacing: 12) {
      if allPassed {
        Button("Done") { dismiss() }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity)
          .accessibilityHint("Closes this sheet and returns to settings")
      }

      if case .failed(let msg) = glassesVM.state {
        Text(msg)
          .font(.caption)
          .foregroundColor(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
          // Live region: VoiceOver announces this text automatically
          // when it appears or changes, without requiring focus.
          .accessibilityAddTraits(.updatesFrequently)
      }
    }
    .padding()
  }

  // MARK: - Step Status Logic

  private var allPassed: Bool {
    ChecklistStep.allCases.allSatisfy { status(for: $0) == .passed }
  }

  private func status(for step: ChecklistStep) -> StepStatus {
    // If any earlier step isn't passed yet, block this one.
    for earlier in ChecklistStep.allCases where earlier.rawValue < step.rawValue {
      if status(for: earlier) != .passed { return .waiting }
    }

    switch step {
    case .bluetooth:
      return glassesVM.isBluetoothOn ? .passed : .failed

    case .registered:
      switch glassesVM.state {
      case .registering: return .inProgress
      case .idle, .unconfigured: return .failed
      default: return .passed
      }

    case .devicesAvailable:
      return glassesVM.availableDevices.isEmpty ? .failed : .passed

    case .deviceActive:
      return glassesVM.isDeviceConnected ? .passed : .failed

    case .cameraPermission:
      switch glassesVM.state {
      case .requestingPermission: return .inProgress
      case .ready, .streaming, .paused: return .passed
      default: return .failed
      }
    }
  }

  // MARK: - Actions

  private func performAction(for step: ChecklistStep) {
    switch step {
    case .bluetooth:
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }

    case .registered:
      glassesVM.resetFailure()
      glassesVM.connectGlasses()

    case .devicesAvailable:
      glassesVM.refreshDevices()

    case .deviceActive:
      Task { await glassesVM.requestCameraPermission() }

    case .cameraPermission:
      Task { await glassesVM.requestCameraPermission() }
    }
  }
}

// MARK: - ChecklistRowView

private struct ChecklistRowView: View {
  let step: ChecklistStep
  let stepNumber: Int
  let totalSteps: Int
  let status: StepStatus
  let action: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        statusIcon
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 2) {
          Text(step.title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(titleColor)
          Text(step.hint)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        if status == .inProgress {
          ProgressView()
            .scaleEffect(0.8)
            // Hidden from the row's combined element; the row label
            // already says "In progress".
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 12)
      // Each row is a single focusable element. The icon and subtitle
      // are presentational — meaning is fully expressed in the label.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(rowAccessibilityLabel)
      .accessibilityHint(step.hint)

      // Action button is a *separate* focusable element so VoiceOver
      // can activate it independently. It sits inside the same visual
      // row but outside the `.ignore` container above.
      if status == .failed {
        HStack {
          Spacer()
          Button(step.actionLabel, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(step.actionHint)
            .accessibilityLabel(step.actionLabel)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
      }
    }
  }

  // MARK: - Helpers

  private var statusIcon: some View {
    Group {
      switch status {
      case .passed:
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
      case .inProgress:
        Image(systemName: "clock.fill")
          .foregroundColor(.orange)
      case .failed:
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.red)
      case .waiting:
        Image(systemName: "circle")
          .foregroundColor(.gray.opacity(0.4))
      }
    }
    .font(.title3)
    // The icon is purely decorative; status is expressed in the label.
    .accessibilityHidden(true)
  }

  private var titleColor: Color {
    switch status {
    case .passed: return .primary
    case .inProgress: return .orange
    case .failed: return .primary
    case .waiting: return .secondary
    }
  }

  /// Full spoken description of this row. Encodes position, name, and
  /// status without relying on color, icon, or layout.
  private var rowAccessibilityLabel: String {
    let statusPhrase: String
    switch status {
    case .passed: statusPhrase = "Complete"
    case .inProgress: statusPhrase = "In progress"
    case .failed: statusPhrase = "Action required"
    case .waiting: statusPhrase = "Not yet available"
    }
    return "Step \(stepNumber) of \(totalSteps): \(step.title). \(statusPhrase)."
  }
}

// MARK: - Preview

#Preview {
  MetaGlassesSetupView()
    .environmentObject(MetaGlassesViewModel.shared)
}
