//  URLSessionProtocol.swift
//  thing-finder
//
//  Protocol abstraction for URLSession to enable dependency injection
//  and mocking in tests.

import Combine
import Foundation

/// Protocol that abstracts URLSession for testability.
/// Allows injection of mock implementations that return canned responses.
public protocol URLSessionProtocol {
  /// Creates a publisher for a URL request that emits data and response.
  func dataTaskPublisherForRequest(_ request: URLRequest) -> AnyPublisher<
    (data: Data, response: URLResponse), URLError
  >
}

// MARK: - URLSession Conformance

extension URLSession: URLSessionProtocol {
  public func dataTaskPublisherForRequest(_ request: URLRequest) -> AnyPublisher<
    (data: Data, response: URLResponse), URLError
  > {
    return self.dataTaskPublisher(for: request)
      .map { ($0.data, $0.response) }
      .eraseToAnyPublisher()
  }
}
