//  VerificationStrategy.swift
//  thing-finder
//
//  Unified verification strategy interface that simplifies the verification
//  system by providing a common interface for all verification approaches.
//
//  Created by Cascade AI.

import Combine
import Foundation
import UIKit

// MARK: - Core Strategy Protocol

/// Unified interface for all verification strategies.
///
/// This protocol defines the contract that all verification strategies must
/// implement, providing a common way to verify candidates regardless of
/// the underlying verification technology.
///
/// ## Topics
///
/// ### Essential Properties
/// - ``strategyName``
///
/// ### Verification Methods
/// - ``verify(image:candidate:)``
/// - ``shouldUse(for:)``
/// - ``priority(for:)``
public protocol VerificationStrategy {
    /// The strategy's identifier for logging and debugging.
    var strategyName: String { get }
    
    /// Verify an image against the target description.
    ///
    /// This method analyzes the provided image and determines if it matches
    /// the target description using the strategy's verification approach.
    ///
    /// - Parameters:
    ///   - image: The cropped image to verify
    ///   - candidate: The candidate being verified (for context)
    /// - Returns: Publisher that emits verification outcome
    func verify(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error>
    
    /// Check if this strategy should be used for the given candidate.
    ///
    /// Determines whether this strategy is appropriate for the given candidate
    /// based on the candidate's characteristics and verification history.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: True if this strategy is appropriate for the candidate
    func shouldUse(for candidate: Candidate) -> Bool
    
    /// Get the priority of this strategy (higher = more preferred).
    ///
    /// Calculates a priority score for this strategy based on the candidate's
    /// characteristics and verification history. Higher scores indicate that
    /// this strategy should be preferred over others.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: Priority score (0-100)
    func priority(for candidate: Candidate) -> Int
}

// MARK: - Strategy Selection

/// Manages strategy selection and execution.
///
/// This class is responsible for selecting the most appropriate verification
/// strategy for a given candidate and executing the verification process.
/// It also handles counter management when switching between strategies.
///
/// ## Topics
///
/// ### Creating a Strategy Manager
/// - ``init(strategies:config:)``
///
/// ### Strategy Selection
/// - ``selectStrategy(for:)``
///
/// ### Verification
/// - ``verify(image:candidate:store:)``
/// - ``verify(image:candidate:)``
public class VerificationStrategyManager {
    /// Available verification strategies.
    public let strategies: [VerificationStrategy]
    
    /// The target text description to verify against.
    public let targetTextDescription: String?
    
    /// Configuration for the verification process.
    private let config: VerificationConfig
    
    /// Initializes a new strategy manager with the provided strategies and configuration.
    ///
    /// - Parameters:
    ///   - strategies: Array of available verification strategies
    ///   - config: Configuration for the verification process
    public init(
        strategies: [VerificationStrategy],
        config: VerificationConfig,
        targetTextDescription: String? = nil
    ) {
        self.strategies = strategies
        self.config = config
        self.targetTextDescription = targetTextDescription
    }
    
    /// Select the best strategy for a given candidate.
    ///
    /// This method filters the available strategies to those that are suitable
    /// for the given candidate and selects the one with the highest priority.
    ///
    /// - Parameter candidate: The candidate to verify
    /// - Returns: The most appropriate strategy, or nil if none are suitable
    public func selectStrategy(for candidate: Candidate) -> VerificationStrategy? {
        return strategies
            .filter { $0.shouldUse(for: candidate) }
            .max { $0.priority(for: candidate) < $1.priority(for: candidate) }
    }
    
    /// Verify a candidate using the best available strategy with proper counter management.
    ///
    /// This method selects the best strategy for the given candidate, resets the appropriate
    /// counters when switching strategies, and performs the verification.
    ///
    /// - Parameters:
    ///   - image: The image to verify
    ///   - candidate: The candidate being verified
    ///   - store: The candidate store for updating counters
    /// - Returns: Publisher that emits verification outcome and selected strategy info
    /// - Throws: `VerificationError.noSuitableStrategy` if no suitable strategy is found
    public func verify(image: UIImage, candidate: Candidate, store: CandidateStore) -> AnyPublisher<(VerificationOutcome, String), Error> {
        guard let strategy = selectStrategy(for: candidate) else {
            return Fail(error: VerificationError.noSuitableStrategy)
                .eraseToAnyPublisher()
        }
        
        // Reset opposite counter when switching strategies (matching original logic)
        if config.useCombinedVerifier {
            store.update(id: candidate.id) {
                if strategy.strategyName.contains("TrafficEye") {
                    $0.verificationTracker.llmAttempts = 0
                } else {
                    $0.verificationTracker.trafficAttempts = 0
                }
            }
        }
        
        return strategy.verify(image: image, candidate: candidate)
            .map { outcome in (outcome, strategy.strategyName) }
            .handleEvents(receiveOutput: { outcome, strategyName in
                print("[VerificationStrategy] \(strategyName) result: match=\(outcome.isMatch)")
            })
            .eraseToAnyPublisher()
    }
    
    /// Legacy verify method for backwards compatibility.
    ///
    /// This method provides a simplified interface for verification without
    /// counter management, primarily for backwards compatibility.
    ///
    /// - Parameters:
    ///   - image: The image to verify
    ///   - candidate: The candidate being verified
    /// - Returns: Publisher that emits verification outcome
    /// - Throws: `VerificationError.noSuitableStrategy` if no suitable strategy is found
    public func verify(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
        guard let strategy = selectStrategy(for: candidate) else {
            return Fail(error: VerificationError.noSuitableStrategy)
                .eraseToAnyPublisher()
        }
        
        return strategy.verify(image: image, candidate: candidate)
            .handleEvents(receiveOutput: { outcome in
                print("[VerificationStrategy] \(strategy.strategyName) result: match=\(outcome.isMatch)")
            })
            .eraseToAnyPublisher()
    }
}

// MARK: - Errors

/// Errors that can occur during the verification process.
///
/// This enum defines the various errors that can occur during verification,
/// providing specific error cases and human-readable descriptions.
///
/// ## Topics
///
/// ### Error Cases
/// - ``noSuitableStrategy``
/// - ``strategyFailed(_:)``
/// - ``timeout``
public enum VerificationError: Error, LocalizedError {
    /// No suitable strategy was found for the candidate.
    case noSuitableStrategy
    
    /// A strategy failed with the specified reason.
    case strategyFailed(String)
    
    /// The verification process timed out.
    case timeout
    
    /// Human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .noSuitableStrategy:
            return "No suitable verification strategy found"
        case .strategyFailed(let reason):
            return "Verification strategy failed: \(reason)"
        case .timeout:
            return "Verification timed out"
        }
    }
}
