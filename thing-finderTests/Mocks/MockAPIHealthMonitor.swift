//  MockAPIHealthMonitor.swift
//  thing-finderTests
//
//  Test double for APIHealthMonitorProtocol used in NetworkFeedbackControllerTests.

import Combine
import Foundation

@testable import thing_finder

final class MockAPIHealthMonitor: APIHealthMonitorProtocol {
  private let subject: CurrentValueSubject<Bool, Never>
  private(set) var recordFailureCallCount = 0
  private(set) var recordSuccessCallCount = 0
  private(set) var lastFailureWasConnectivityRelated: Bool?

  init(isDegraded: Bool = false) {
    subject = CurrentValueSubject(isDegraded)
  }

  var isDegraded: Bool {
    get { subject.value }
    set { subject.send(newValue) }
  }

  var degradedPublisher: AnyPublisher<Bool, Never> {
    subject.removeDuplicates().eraseToAnyPublisher()
  }

  func recordFailure(isConnectivityRelated: Bool) {
    recordFailureCallCount += 1
    lastFailureWasConnectivityRelated = isConnectivityRelated
  }

  func recordSuccess() {
    recordSuccessCallCount += 1
  }
}
