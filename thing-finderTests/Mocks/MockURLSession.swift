//  MockURLSession.swift
//  thing-finderTests
//
//  Mock implementation of URLSessionProtocol for testing network-dependent code.
//  Allows configuring canned responses for specific URLs.

import Combine
import Foundation

@testable import thing_finder

/// Mock URLSession that returns pre-configured responses for testing.
final class MockURLSession: URLSessionProtocol {

  /// Response configuration for a specific URL pattern.
  struct MockResponse {
    let data: Data
    let statusCode: Int
    let error: URLError?

    init(data: Data, statusCode: Int = 200, error: URLError? = nil) {
      self.data = data
      self.statusCode = statusCode
      self.error = error
    }

    /// Create a mock response from a JSON-encodable object.
    static func json<T: Encodable>(_ object: T, statusCode: Int = 200) -> MockResponse {
      let data = try! JSONEncoder().encode(object)
      return MockResponse(data: data, statusCode: statusCode)
    }

    /// Create a mock response from a JSON string.
    static func jsonString(_ json: String, statusCode: Int = 200) -> MockResponse {
      return MockResponse(data: json.data(using: .utf8)!, statusCode: statusCode)
    }

    /// Create a mock error response.
    static func error(_ urlError: URLError) -> MockResponse {
      return MockResponse(data: Data(), error: urlError)
    }
  }

  /// Maps URL host/path patterns to mock responses.
  /// Key format: "host/path" or just "host" for any path on that host.
  var responses: [String: MockResponse] = [:]

  /// Default response when no specific match is found.
  var defaultResponse: MockResponse?

  /// Records all requests made through this session.
  private(set) var requestHistory: [URLRequest] = []

  /// Delay to simulate network latency (in seconds).
  var simulatedDelay: TimeInterval = 0

  func dataTaskPublisherForRequest(_ request: URLRequest) -> AnyPublisher<
    (data: Data, response: URLResponse), URLError
  > {
    requestHistory.append(request)

    // Find matching response
    let response = findResponse(for: request)

    // If error configured, return failure
    if let error = response?.error {
      return Fail(error: error)
        .delay(for: .seconds(simulatedDelay), scheduler: DispatchQueue.global())
        .eraseToAnyPublisher()
    }

    // Build HTTP response
    let data = response?.data ?? Data()
    let statusCode = response?.statusCode ?? 200
    let httpResponse = HTTPURLResponse(
      url: request.url!,
      statusCode: statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!

    return Just((data: data, response: httpResponse as URLResponse))
      .delay(for: .seconds(simulatedDelay), scheduler: DispatchQueue.global())
      .setFailureType(to: URLError.self)
      .eraseToAnyPublisher()
  }

  private func findResponse(for request: URLRequest) -> MockResponse? {
    guard let url = request.url else { return defaultResponse }

    // Try exact host/path match
    if let host = url.host {
      let hostPath = "\(host)\(url.path)"
      if let response = responses[hostPath] {
        return response
      }

      // Try host-only match
      if let response = responses[host] {
        return response
      }
    }

    return defaultResponse
  }

  /// Resets all state for clean test setup.
  func reset() {
    responses = [:]
    defaultResponse = nil
    requestHistory = []
    simulatedDelay = 0
  }

  /// Configure a response for a specific host/path.
  func setResponse(_ response: MockResponse, for hostPath: String) {
    responses[hostPath] = response
  }

  /// Configure a JSON response for a specific host/path.
  func setJSONResponse(_ json: String, for hostPath: String, statusCode: Int = 200) {
    responses[hostPath] = .jsonString(json, statusCode: statusCode)
  }
}
