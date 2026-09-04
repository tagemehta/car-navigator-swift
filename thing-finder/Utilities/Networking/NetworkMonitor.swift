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

  /// How long to block for the first `NWPathMonitor` callback before falling
  /// back to an optimistic default. `NWPathMonitor` typically delivers its
  /// first update within a few milliseconds, so this only adds latency on a
  /// genuine cold start — but without it, a Shortcut can launch straight into
  /// the camera before the real (offline) status ever arrives.
  private static let initialStatusTimeout: TimeInterval = 0.3

  private init() {
    let semaphore = DispatchSemaphore(value: 0)
    var initialConnected = true
    monitor.pathUpdateHandler = { path in
      initialConnected = path.status == .satisfied
      semaphore.signal()
    }
    monitor.start(queue: queue)
    _ = semaphore.wait(timeout: .now() + Self.initialStatusTimeout)

    subject = CurrentValueSubject(initialConnected)
    monitor.pathUpdateHandler = { [weak self] path in
      self?.subject.send(path.status == .satisfied)
    }
  }

  deinit {
    monitor.cancel()
  }
}
