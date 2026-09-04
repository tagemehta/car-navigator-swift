//  NetworkErrorClassifier.swift
//  thing-finder
//
//  Distinguishes connectivity-related verification failures (timeouts, DNS
//  failures, dropped connections) from unrelated ones (occlusion, low
//  confidence, wrong vehicle) so `APIHealthMonitor` only reacts to signal
//  problems.

import Foundation

enum NetworkErrorClassifier {
  static func isConnectivityError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
        .dataNotAllowed, .internationalRoamingOff, .callIsActive:
        return true
      default:
        return false
      }
    }
    if let verificationError = error as? VerificationError, case .timeout = verificationError {
      return true
    }
    if let twoStepError = error as? TwoStepError, case .networkError = twoStepError {
      return true
    }
    return false
  }
}
