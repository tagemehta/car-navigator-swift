//  MockNetworkMonitor.swift
//  thing-finderTests
//
//  Test double for NetworkMonitorProtocol used in NetworkFeedbackControllerTests.

import Combine
import Foundation

@testable import thing_finder

final class MockNetworkMonitor: NetworkMonitorProtocol {
  private let subject: CurrentValueSubject<Bool, Never>

  init(isConnected: Bool = true) {
    subject = CurrentValueSubject(isConnected)
  }

  var isConnected: Bool {
    get { subject.value }
    set { subject.send(newValue) }
  }

  var connectionPublisher: AnyPublisher<Bool, Never> {
    subject.removeDuplicates().eraseToAnyPublisher()
  }
}
