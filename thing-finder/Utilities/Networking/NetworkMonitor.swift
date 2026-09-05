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

public final class NetworkMonitor: NetworkMonitorProtocol {
  public static let shared = NetworkMonitor()

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.thingfinder.NetworkMonitor")
  private let subject = CurrentValueSubject<Bool, Never>(true)

  /// Wraps a single continuation so both the real path-update callback and
  /// the timeout fallback can race to resume it exactly once. Both are only
  /// ever invoked from `queue` (a serial queue), so no extra locking is
  /// needed here — the second caller simply finds `continuation` already
  /// `nil` and does nothing.
  private final class PendingWait {
    var continuation: CheckedContinuation<Bool, Never>?
    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }
    func resume(with value: Bool) {
      continuation?.resume(returning: value)
      continuation = nil
    }
  }

  private let lock = NSLock()
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

  private func handlePathUpdate(connected: Bool) {
    subject.send(connected)

    lock.lock()
    hasReceivedInitialPath = true
    let waits = pendingWaits
    pendingWaits = []
    lock.unlock()

    // Runs on `queue`, same as the timeout fallback below, so this can never
    // race with a `PendingWait.resume(with:)` call from `asyncAfter`.
    for wait in waits {
      wait.resume(with: connected)
    }
  }

  public func currentConnectivity() async -> Bool {
    lock.lock()
    if hasReceivedInitialPath {
      let value = subject.value
      lock.unlock()
      return value
    }
    lock.unlock()

    return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      lock.lock()
      // Re-check: the real path update may have arrived between releasing
      // the lock above and entering this closure.
      if hasReceivedInitialPath {
        let value = subject.value
        lock.unlock()
        continuation.resume(returning: value)
        return
      }
      let wait = PendingWait(continuation)
      pendingWaits.append(wait)
      lock.unlock()

      queue.asyncAfter(deadline: .now() + Self.initialStatusTimeout) { [weak self] in
        guard let self else {
          wait.resume(with: true)
          return
        }
        self.lock.lock()
        self.pendingWaits.removeAll { $0 === wait }
        let fallback = self.subject.value
        self.lock.unlock()
        wait.resume(with: fallback)
      }
    }
  }

  deinit {
    monitor.cancel()
  }
}
