//  APIHealthMonitor.swift
//  thing-finder
//
//  Detects a "weak signal" condition: the device reports connectivity (see
//  `NetworkMonitor`), but verification requests keep failing or timing out
//  because of the connection quality. Verifiers report each request outcome
//  here; once enough *connectivity-related* failures happen back-to-back we
//  flag the connection as degraded, and clear the flag on the next success.

import Combine
import Foundation

public protocol APIHealthMonitorProtocol: AnyObject {
  /// True once consecutive connectivity-related failures cross the threshold.
  var isDegraded: Bool { get }
  /// Emits the degraded state whenever it changes (deduplicated).
  var degradedPublisher: AnyPublisher<Bool, Never> { get }
  /// Report the outcome of a verification request.
  /// - Parameter isConnectivityRelated: whether the failure looks like a
  ///   network problem (timeout, DNS failure, lost connection) as opposed to
  ///   an unrelated rejection (e.g. wrong vehicle, low confidence).
  func recordFailure(isConnectivityRelated: Bool)
  /// Report a successful verification request, clearing the degraded state.
  func recordSuccess()
}

public final class APIHealthMonitor: APIHealthMonitorProtocol {
  public static let shared = APIHealthMonitor()

  /// Consecutive connectivity-related failures required before flagging the
  /// connection as degraded.
  private let failureThreshold: Int
  private let lock = NSLock()
  private var consecutiveFailures = 0
  private let subject = CurrentValueSubject<Bool, Never>(false)

  public var isDegraded: Bool { subject.value }

  public var degradedPublisher: AnyPublisher<Bool, Never> {
    subject.removeDuplicates().eraseToAnyPublisher()
  }

  init(failureThreshold: Int = 3) {
    self.failureThreshold = failureThreshold
  }

  public func recordFailure(isConnectivityRelated: Bool) {
    guard isConnectivityRelated else { return }
    lock.lock()
    defer { lock.unlock() }
    consecutiveFailures += 1
    // Publish while still holding the lock: a concurrent `recordSuccess()`
    // must not be able to reset the counter between our check and the
    // publish, which would otherwise flag a stale failure as "degraded"
    // right after a request had actually succeeded.
    if consecutiveFailures >= failureThreshold && !subject.value {
      subject.send(true)
    }
  }

  public func recordSuccess() {
    lock.lock()
    defer { lock.unlock() }
    consecutiveFailures = 0
    if subject.value {
      subject.send(false)
    }
  }
}
