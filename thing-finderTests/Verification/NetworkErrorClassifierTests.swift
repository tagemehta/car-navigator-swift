//  NetworkErrorClassifierTests.swift
//  thing-finderTests
//
//  Unit tests for NetworkErrorClassifier.

import XCTest

@testable import thing_finder

final class NetworkErrorClassifierTests: XCTestCase {

  func test_urlError_notConnectedToInternet_isConnectivityError() {
    let error = URLError(.notConnectedToInternet)
    XCTAssertTrue(NetworkErrorClassifier.isConnectivityError(error))
  }

  func test_urlError_timedOut_isConnectivityError() {
    let error = URLError(.timedOut)
    XCTAssertTrue(NetworkErrorClassifier.isConnectivityError(error))
  }

  func test_urlError_networkConnectionLost_isConnectivityError() {
    let error = URLError(.networkConnectionLost)
    XCTAssertTrue(NetworkErrorClassifier.isConnectivityError(error))
  }

  func test_urlError_badServerResponse_isNotConnectivityError() {
    let error = URLError(.badServerResponse)
    XCTAssertFalse(NetworkErrorClassifier.isConnectivityError(error))
  }

  func test_verificationError_timeout_isConnectivityError() {
    XCTAssertTrue(NetworkErrorClassifier.isConnectivityError(VerificationError.timeout))
  }

  func test_twoStepError_networkError_isConnectivityError() {
    XCTAssertTrue(NetworkErrorClassifier.isConnectivityError(TwoStepError.networkError))
  }

  func test_twoStepError_occluded_isNotConnectivityError() {
    XCTAssertFalse(NetworkErrorClassifier.isConnectivityError(TwoStepError.occluded))
  }

  func test_twoStepError_noToolResponse_isNotConnectivityError() {
    XCTAssertFalse(NetworkErrorClassifier.isConnectivityError(TwoStepError.noToolResponse))
  }

  func test_unrelatedError_isNotConnectivityError() {
    struct SomeError: Error {}
    XCTAssertFalse(NetworkErrorClassifier.isConnectivityError(SomeError()))
  }
}
