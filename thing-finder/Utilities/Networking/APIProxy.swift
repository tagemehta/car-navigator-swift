//  APIProxy.swift
//  thing-finder
//
//  Verifier network calls go through the CurbToCar Cloudflare Worker (`proxy/`), which holds the
//  OpenAI and TrafficEye keys. The app only sends its app token and a per-install device ID.

import Foundation

struct APIProxy {
  let baseURL: URL
  let appToken: String
  let deviceId: String

  /// Reads `PROXY_BASE_URL` and `PROXY_APP_TOKEN` from Info.plist (set in Secrets.xcconfig).
  /// A missing URL falls back to an unreachable host, so requests fail at the network rather than at startup.
  static let shared = APIProxy(
    baseURL: URL(string: Bundle.main.infoDictionary?["PROXY_BASE_URL"] as? String ?? "")
      ?? URL(string: "https://proxy.invalid")!,
    appToken: Bundle.main.infoDictionary?["PROXY_APP_TOKEN"] as? String ?? "",
    deviceId: installId()
  )

  var chatCompletionsURL: URL { baseURL.appendingPathComponent("v1/chat/completions") }
  var recognitionURL: URL { baseURL.appendingPathComponent("recognition") }

  /// Adds the proxy auth headers. The proxy rate-limits per device ID.
  func authorize(_ request: inout URLRequest) {
    request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
    request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
  }

  private static func installId(defaults: UserDefaults = .standard) -> String {
    let key = "apiProxyInstallId"
    if let existing = defaults.string(forKey: key) { return existing }
    let id = UUID().uuidString
    defaults.set(id, forKey: key)
    return id
  }
}
