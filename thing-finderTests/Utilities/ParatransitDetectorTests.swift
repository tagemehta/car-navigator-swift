//  ParatransitDetectorTests.swift
//  thing-finderTests

import XCTest

@testable import thing_finder

final class ParatransitDetectorTests: XCTestCase {
  private func response(category: String) -> MockURLSession.MockResponse {
    let args = "{\\\"category\\\":\\\"\(category)\\\"}"
    return .jsonString(
      """
      {"choices":[{"message":{"content":null,"refusal":null,"tool_calls":[{"function":{"name":"classify_vehicle_request","arguments":"\(args)"}}]}}]}
      """)
  }

  private func detector(_ session: MockURLSession) -> ParatransitDetector {
    ParatransitDetector(session: session)
  }

  func test_transitVehicle_isParatransit() async throws {
    let session = MockURLSession()
    session.defaultResponse = response(category: "service_vehicle")
    let result = try await detector(session).isParatransit(description: "Route 42 bus")
    XCTAssertTrue(result)
  }

  func test_rideshareCar_isNotParatransit() async throws {
    let session = MockURLSession()
    session.defaultResponse = response(category: "make_model_car")
    let result = try await detector(session).isParatransit(description: "white Toyota Camry")
    XCTAssertFalse(result)
  }

  func test_networkError_throws() async {
    let session = MockURLSession()
    session.defaultResponse = .error(URLError(.notConnectedToInternet))
    do {
      _ = try await detector(session).isParatransit(description: "blue Honda")
      XCTFail("expected throw")
    } catch {}
  }
}
