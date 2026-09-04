//  NetworkMonitor.swift
//  thing-finder
//
//  Reports hard connectivity loss (airplane mode, no Wi-Fi/cellular path at
//  all). Wraps `NWPathMonitor` behind a protocol so navigation feedback can
//  be unit-tested without depending on the real network stack.
//
//  Note: this can only tell you whether the OS believes it has *a* usable
//  network path — it cannot detect a merely weak/slow connection where
//  requests still time out. See `APIHealthMonitor` for that signal.

import Combine
import Foundation
import Network

public protocol NetworkMonitorProtocol: AnyObject {
  /// True when the OS reports a usable network path.
  var isConnected: Bool { get }
  /// Emits the connectivity state whenever it changes (deduplicated).
  var connectionPublisher: AnyPublisher<Bool, Never> { get }
}

public final class NetworkMonitor: NetworkMonitorProtocol {
  public static let shared = NetworkMonitor()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.thingfinder.NetworkMonitor")
  private let subject: CurrentValueSubject<Bool, Never>

  public var isConnected: Bool { subject.value }

  public var connectionPublisher: AnyPublisher<Bool, Never> {
    subject.removeDuplicates().eraseToAnyPublisher()
  }

  private init() {
    // Optimistic default so we never announce a false "offline" before the
    // first path update arrives.
    subject = CurrentValueSubject(true)
    monitor.pathUpdateHandler = { [weak self] path in
      self?.subject.send(path.status == .satisfied)
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}
