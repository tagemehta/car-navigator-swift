/// TelemetryService
/// -----------------
/// Consent-gated analytics via the PostHog iOS SDK.
///
/// Usage:
///   TelemetryService.shared.setupSDK()
///   TelemetryService.shared.recordSessionStarted(...)
///
/// All capture methods are no-ops when consent is .declined or .notAsked.
/// Mutable state is protected by a serial dispatch queue for thread safety.

import Foundation
import PostHog

public final class TelemetryService {

  public static let shared = TelemetryService()
  private init() {}

  // MARK: - Synchronisation

  private let queue = DispatchQueue(label: "com.curb2car.telemetry", qos: .utility)

  // MARK: - Configuration

  private var sdkConfigured = false

  /// Set up the PostHog SDK once. Safe to call multiple times; only the first
  /// call with accepted consent actually initialises the SDK.
  public func setupSDKIfConsented() {
    queue.sync {
      guard !sdkConfigured else { return }
      guard consentIsAccepted else { return }
      let key = Bundle.main.infoDictionary?["POSTHOG_API_KEY"] as? String ?? ""
      guard !key.isEmpty else { return }
      let config = PostHogConfig(apiKey: key)
      config.captureScreenViews = false
      config.captureApplicationLifecycleEvents = false
      config.enableSwizzling = false
      config.surveys = false
      PostHogSDK.shared.setup(config)
      PostHogSDK.shared.optIn()
      sdkConfigured = true
    }
  }

  /// Call when consent changes. If the SDK has been set up, opts in or out
  /// of PostHog data transmission accordingly.
  public func updateConsentState() {
    queue.sync {
      guard sdkConfigured else { return }
      if consentIsAccepted {
        PostHogSDK.shared.optIn()
      } else {
        PostHogSDK.shared.optOut()
      }
    }
  }

  // MARK: - Session State (accessed only inside `queue`)

  private var sessionStartTime: Date?
  private var sessionFound = false
  private var totalCandidates = 0
  private var seenCandidateIDs: Set<UUID> = []
  private var usedOCR = false
  private var firstDetectionEmitted = false

  // MARK: - Public API

  public func recordSessionStarted(
    hasPlate: Bool,
    strategy: String,
    searchMode: String
  ) {
    setupSDKIfConsented()

    queue.sync {
      sessionStartTime = Date()
      sessionFound = false
      totalCandidates = 0
      seenCandidateIDs = []
      usedOCR = false
      firstDetectionEmitted = false
    }

    capture(
      "session_started",
      properties: [
        "has_plate": hasPlate,
        "strategy": strategy,
        "search_mode": searchMode,
      ])
  }

  /// Call once when the first vehicle detection occurs in a session.
  public func recordFirstDetectionIfNeeded() {
    var elapsed: TimeInterval?
    queue.sync {
      guard !firstDetectionEmitted, let start = sessionStartTime else { return }
      firstDetectionEmitted = true
      elapsed = Date().timeIntervalSince(start)
    }
    guard let elapsed else { return }
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
    queue.sync {
      sessionFound = true
    }
  }

  /// Call each time a candidate first enters verification.
  /// Tracks unique candidates by ID so retries are not double-counted.
  public func incrementCandidates(id: UUID) {
    queue.sync {
      if seenCandidateIDs.insert(id).inserted {
        totalCandidates += 1
      }
    }
  }

  /// Call when the verifier returns a match but the candidate was lost or
  /// removed from the store before the result could be applied.
  public func recordMatchDiscarded(reason: String, latencyMs: Int) {
    capture(
      "match_discarded",
      properties: [
        "reason": reason,
        "latency_ms": latencyMs,
      ])
  }

  /// Call when OCR is first attempted in this session.
  public func markOCRUsed() {
    queue.sync {
      usedOCR = true
    }
  }

  /// Call when the user explicitly ends a search session (e.g. navigates back).
  public func recordSessionEnded() {
    var duration: TimeInterval = 0
    var found = false
    var candidates = 0
    var ocr = false
    var hadSession = false
    queue.sync {
      guard sessionStartTime != nil else { return }
      hadSession = true
      duration = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
      found = sessionFound
      candidates = totalCandidates
      ocr = usedOCR
      sessionStartTime = nil
    }
    guard hadSession else { return }
    capture(
      "session_ended",
      properties: [
        "outcome": found ? "found" : "abandoned",
        "duration_s": duration,
        "total_candidates": candidates,
        "used_ocr": ocr,
      ])
  }

  // MARK: - Private

  /// Read consent directly from UserDefaults to avoid holding a weak/strong
  /// reference to a Settings object that may be deallocated.
  private var consentIsAccepted: Bool {
    let raw = UserDefaults.standard.string(forKey: "telemetry_consent") ?? ""
    return raw == TelemetryConsent.accepted.rawValue
  }

  private func capture(_ event: String, properties: [String: Any]) {
    guard consentIsAccepted else { return }
    PostHogSDK.shared.capture(event, properties: properties)
  }
}
