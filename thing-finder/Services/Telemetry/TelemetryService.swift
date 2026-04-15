/// TelemetryService
/// -----------------
/// Consent-gated analytics. Posts events to PostHog via a direct HTTP call —
/// no SDK dependency required.
///
/// Usage:
///   TelemetryService.shared.configure(settings: settings)
///   TelemetryService.shared.recordSessionStarted(...)
///
/// All capture methods are no-ops when consent is .declined or .notAsked.

import Foundation
import UIKit

public final class TelemetryService {

  public static let shared = TelemetryService()
  private init() {}

  // MARK: - Configuration

  private weak var settings: Settings?

  public func configure(settings: Settings) {
    self.settings = settings
  }

  // MARK: - Session State

  private var sessionStartTime: Date?
  private var sessionFound = false
  private var totalCandidates = 0
  private var usedOCR = false
  private var firstDetectionEmitted = false

  // MARK: - Public API

  public func recordSessionStarted(
    vehicleType: String,
    hasPlate: Bool,
    strategy: String,
    searchMode: String
  ) {
    sessionStartTime = Date()
    sessionFound = false
    totalCandidates = 0
    usedOCR = false
    firstDetectionEmitted = false

    capture(
      "session_started",
      properties: [
        "vehicle_type": vehicleType,
        "has_plate": hasPlate,
        "strategy": strategy,
        "search_mode": searchMode,
      ])
  }

  /// Call once when the first vehicle detection occurs in a session.
  public func recordFirstDetectionIfNeeded() {
    guard !firstDetectionEmitted, let start = sessionStartTime else { return }
    firstDetectionEmitted = true
    let elapsed = Date().timeIntervalSince(start)
    capture(
      "first_detection",
      properties: [
        "time_to_first_detection_s": elapsed
      ])
  }

  /// Call after each verifier API call completes.
  public func recordVerificationAttempt(
    verifier: String,
    outcome: String,
    durationMs: Int,
    rejectReason: String?
  ) {
    var props: [String: Any] = [
      "verifier": verifier,
      "outcome": outcome,
      "duration_ms": durationMs,
    ]
    if let reason = rejectReason {
      props["reject_reason"] = reason
    }
    capture("verification_attempt", properties: props)
  }

  /// Call when the pipeline phase transitions to .found.
  public func markSessionFound() {
    sessionFound = true
  }

  /// Call each time a new candidate is created.
  public func incrementCandidates() {
    totalCandidates += 1
  }

  /// Call when OCR is first attempted in this session.
  public func markOCRUsed() {
    usedOCR = true
  }

  /// Call from ContentView.onDisappear to close out the session.
  public func recordSessionEnded() {
    let duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
    capture(
      "session_ended",
      properties: [
        "outcome": sessionFound ? "found" : "abandoned",
        "duration_s": duration,
        "total_candidates": totalCandidates,
        "used_ocr": usedOCR,
      ])
    sessionStartTime = nil
  }

  // MARK: - Private

  private var apiKey: String {
    Bundle.main.infoDictionary?["POSTHOG_API_KEY"] as? String ?? ""
  }

  private var distinctId: String {
    let key = "telemetry_distinct_id"
    if let stored = UserDefaults.standard.string(forKey: key) { return stored }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: key)
    return newId
  }

  private func capture(_ event: String, properties: [String: Any]) {
    guard settings?.telemetryConsent == .accepted else { return }
    let key = apiKey
    guard !key.isEmpty else { return }

    var payload: [String: Any] = [
      "api_key": key,
      "event": event,
      "distinct_id": distinctId,
      "properties": properties,
    ]
    payload["timestamp"] = ISO8601DateFormatter().string(from: Date())

    guard let url = URL(string: "https://us.i.posthog.com/capture/"),
      let body = try? JSONSerialization.data(withJSONObject: payload)
    else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    URLSession.shared.dataTask(with: request) { _, _, error in
      if let error = error {
        print("[Telemetry] Capture failed: \(error.localizedDescription)")
      }
    }.resume()
  }
}
