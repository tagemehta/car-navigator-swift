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
  /// Best-known connectivity state. Before the first real `NWPathMonitor`
  /// callback arrives this is an optimistic guess (`true`) — use
  /// `currentConnectivity()` instead when a wrong guess would let a caller
  /// (e.g. search startup) proceed offline unannounced.
  var isConnected: Bool { get }
  /// Emits the connectivity state whenever it changes (deduplicated).
  var connectionPublisher: AnyPublisher<Bool, Never> { get }
  /// Resolves to the *real* connectivity state, suspending until the first
  /// `NWPathMonitor` callback has been delivered (if it hasn't already).
  /// Falls back to the optimistic `isConnected` guess if no callback arrives
  /// within a short timeout, so this can never hang indefinitely.
  func currentConnectivity() async -> Bool
}

public final class NetworkMonitor: NetworkMonitorProtocol, @unchecked Sendable {
  public static let shared = NetworkMonitor()

  private let monitor = NWPathMonitor()
  /// All mutable state below is accessed on this serial queue. The explicit
  /// Sendable conformance is limited to allowing Network framework callbacks
  /// and timeout closures to capture this queue-confined object.
  private let queue = DispatchQueue(label: "com.thingfinder.NetworkMonitor")
  private let subject = CurrentValueSubject<Bool, Never>(true)

  /// A continuation can be completed by either the first path update or the
  /// timeout fallback. Both callbacks run on `queue`, so clearing the
  /// continuation before returning prevents a double resume without locks.
  private final class PendingWait: @unchecked Sendable {
    var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
      self.continuation = continuation
    }

    func resume(with value: Bool) {
      continuation?.resume(returning: value)
      continuation = nil
    }
  }

  private var hasReceivedInitialPath = false
  private var pendingWaits: [PendingWait] = []

  /// How long `currentConnectivity()` will wait for the first real
  /// `NWPathMonitor` callback before falling back to the optimistic default.
  /// `NWPathMonitor` typically delivers its first update within a few
  /// milliseconds, so this only adds latency on a genuine cold start — but
  /// without it, a Shortcut could launch straight into the camera before the
  /// real (offline) status ever arrives.
  private static let initialStatusTimeout: TimeInterval = 0.3

  public var isConnected: Bool { subject.value }

  public var connectionPublisher: AnyPublisher<Bool, Never> {
    subject.removeDuplicates().eraseToAnyPublisher()
  }

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.handlePathUpdate(connected: path.status == .satisfied)
    }
    monitor.start(queue: queue)
  }

  /// Called by `NWPathMonitor` on `queue`.
  private func handlePathUpdate(connected: Bool) {
    subject.send(connected)
    hasReceivedInitialPath = true

    let waits = pendingWaits
    pendingWaits.removeAll()
    for wait in waits {
      wait.resume(with: connected)
    }
  }

  public func currentConnectivity() async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      // Registration and timeout both happen on the monitor's serial queue.
      // This avoids suspending while holding a lock and makes the path update,
      // timeout, and pending-wait state one easy-to-follow synchronization
      // domain.
      queue.async { [weak self] in
        guard let self else {
          continuation.resume(returning: true)
          return
        }

        if self.hasReceivedInitialPath {
          continuation.resume(returning: self.subject.value)
          return
        }

        let wait = PendingWait(continuation)
        self.pendingWaits.append(wait)
        self.queue.asyncAfter(deadline: .now() + Self.initialStatusTimeout) { [weak self, wait] in
          guard let self else {
            wait.resume(with: true)
            return
          }

          self.pendingWaits.removeAll { $0 === wait }
          wait.resume(with: self.subject.value)
        }
      }
    }
  }

  deinit {
    monitor.cancel()
  }
}
