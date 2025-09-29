//  BaseVerificationStrategy.swift
//  thing-finder
//
//  Base implementation for verification strategies that provides common
//  functionality like retry logic, attempt tracking, and error handling.
//
//  Created by Cascade AI.

import Combine
import Foundation
import UIKit

// MARK: - Base Strategy Implementation

/// Base class that provides common verification functionality.
///
/// This abstract class implements the ``VerificationStrategy`` protocol and provides
/// shared functionality for all concrete verification strategies, including error handling,
/// timeout management, and helper methods for strategy selection.
///
/// ## Topics
///
/// ### Creating a Strategy
/// - ``init(strategyName:targetTextDescription:config:)``
///
/// ### VerificationStrategy Protocol Implementation
/// - ``verify(image:candidate:)``
/// - ``shouldUse(for:)``
/// - ``priority(for:)``
///
/// ### Common Functionality
/// - ``performVerification(image:candidate:)``
/// - ``handleVerificationError(_:for:)``
/// - ``timeSinceLastVerification()``
/// - ``meetsBasicRequirements(_:)``
/// - ``shouldRetry(candidate:strategyType:)``
///
/// ### Selection Helpers
/// - ``calculatePriority(basePriority:for:strategyType:)``
public class BaseVerificationStrategy: VerificationStrategy {
    
    // MARK: - Properties
    
    /// The strategy's identifier for logging and debugging.
    public let strategyName: String
    
    /// The target text description to verify against.
    public let targetTextDescription: String
    
    /// Configuration for the verification process.
    internal let config: VerificationConfig
    
    /// The date of the last verification attempt.
    private var lastVerifiedDate = Date()
    
    // MARK: - Initialization
    
    /// Initializes a new verification strategy with the provided parameters.
    ///
    /// - Parameters:
    ///   - strategyName: The identifier for this strategy
    ///   - targetTextDescription: The target text description to verify against
    ///   - config: Configuration for the verification process
    public init(
        strategyName: String,
        targetTextDescription: String,
        config: VerificationConfig
    ) {
        self.strategyName = strategyName
        self.targetTextDescription = targetTextDescription
        self.config = config
    }
    
    // MARK: - VerificationStrategy Protocol
    
    /// Verify an image against the target description.
    ///
    /// This method sets up the verification process with proper error handling and timeout management,
    /// then delegates the actual verification to the `performVerification` method that subclasses must implement.
    ///
    /// - Parameters:
    ///   - image: The cropped image to verify
    ///   - candidate: The candidate being verified (for context)
    /// - Returns: Publisher that emits verification outcome
    public func verify(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
        let startTime = Date()
        lastVerifiedDate = startTime
        
        return performVerification(image: image, candidate: candidate)
            .handleEvents(receiveOutput: { outcome in
                let latency = Date().timeIntervalSince(startTime)
                DebugPublisher.shared.info(
                    "[Strategy][\(candidate.id.uuidString.suffix(8))] \(self.strategyName) completed in \(String(format: "%.3f", latency))s"
                )
            })
            .timeout(.seconds(5), scheduler: DispatchQueue.main)
            .catch { [weak self] error -> AnyPublisher<VerificationOutcome, Error> in
                guard let self = self else {
                    return Fail(error: VerificationError.strategyFailed("Strategy deallocated"))
                        .eraseToAnyPublisher()
                }
                
                return self.handleVerificationError(error, for: candidate)
            }
            .eraseToAnyPublisher()
    }
    
    /// Check if this strategy should be used for the given candidate.
    ///
    /// Default implementation returns true. Subclasses should override this method
    /// to provide specific selection logic.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: True if this strategy is appropriate for the candidate
    public func shouldUse(for candidate: Candidate) -> Bool {
        // Default implementation - subclasses should override
        return true
    }
    
    /// Get the priority of this strategy (higher = more preferred).
    ///
    /// Default implementation returns a medium priority (50).
    /// Subclasses should override this method to provide specific priority logic.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: Priority score (0-100)
    public func priority(for candidate: Candidate) -> Int {
        // Default implementation - subclasses should override
        return 50
    }
    
    // MARK: - Abstract Methods
    
    /// Perform the actual verification - must be implemented by subclasses.
    ///
    /// This is an abstract method that concrete subclasses must implement to provide
    /// their specific verification logic.
    ///
    /// - Parameters:
    ///   - image: The image to verify
    ///   - candidate: The candidate being verified
    /// - Returns: Publisher that emits verification outcome
    internal func performVerification(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
        fatalError("performVerification must be implemented by subclasses")
    }
    
    // MARK: - Common Functionality
    
    /// Handle verification errors and convert them to appropriate outcomes.
    ///
    /// This method processes errors that occur during verification and converts them
    /// to appropriate rejection outcomes with specific reasons.
    ///
    /// - Parameters:
    ///   - error: The error that occurred during verification
    ///   - candidate: The candidate being verified
    /// - Returns: Publisher that emits a rejection outcome with an appropriate reason
    internal func handleVerificationError(_ error: Error, for candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
        let rejectReason: RejectReason
        
        if let twoStepError = error as? TwoStepError {
            switch twoStepError {
            case .noToolResponse, .networkError:
                rejectReason = .apiError
            case .occluded:
                rejectReason = .unclearImage
            case .lowConfidence:
                rejectReason = .lowConfidence
            }
        } else {
            rejectReason = .apiError
        }
        
        let outcome = VerificationOutcome(
            isMatch: false,
            description: "",
            rejectReason: rejectReason
        )
        
        return Just(outcome)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    /// Get time since last verification.
    ///
    /// - Returns: Time interval since the last verification attempt
    public func timeSinceLastVerification() -> TimeInterval {
        Date().timeIntervalSince(lastVerifiedDate)
    }
    
    /// Check if the candidate meets basic verification requirements.
    ///
    /// This method validates that the candidate's bounding box has a reasonable
    /// size and aspect ratio before attempting verification.
    ///
    /// - Parameter candidate: The candidate to check
    /// - Returns: True if the candidate meets basic requirements for verification
    internal func meetsBasicRequirements(_ candidate: Candidate) -> Bool {
        // Check bounding box size
        let bboxArea = candidate.lastBoundingBox.width * candidate.lastBoundingBox.height
        let minAreaThreshold: CGFloat = 0.01 // 1% of the image
        
        if bboxArea < minAreaThreshold {
            return false
        }
        
        // Check aspect ratio (avoid very tall/narrow boxes)
        let aspectRatio = candidate.lastBoundingBox.height / max(candidate.lastBoundingBox.width, 0.0001)
        let maxTallness: CGFloat = 3 // height cannot exceed 300% of width
        
        if aspectRatio > maxTallness {
            return false
        }
        
        return true
    }
    
    /// Determine if we should retry based on attempt counts.
    ///
    /// This method checks if the number of attempts for a specific strategy type
    /// has exceeded the configured maximum.
    ///
    /// - Parameters:
    ///   - candidate: The candidate being verified
    ///   - strategyType: The type of verification strategy
    /// - Returns: True if another attempt should be made with this strategy
    internal func shouldRetry(candidate: Candidate, strategyType: VerifierKind) -> Bool {
        switch strategyType {
        case .trafficEye:
            return candidate.verificationTracker.trafficAttempts < VerificationPolicy.maxPrimaryRetries
        case .llm:
            return candidate.verificationTracker.llmAttempts < VerificationPolicy.maxLLMRetries
        }
    }
}

// MARK: - Strategy Selection Helpers

extension BaseVerificationStrategy {
    
    /// Calculate priority based on candidate characteristics and attempt history.
    ///
    /// This method adjusts the base priority of a strategy based on the candidate's
    /// characteristics (like view angle) and verification history (like previous attempts).
    /// It implements the dynamic switching logic between strategies.
    ///
    /// - Parameters:
    ///   - basePriority: The starting priority value (0-100)
    ///   - candidate: The candidate being verified
    ///   - strategyType: The type of verification strategy
    /// - Returns: Adjusted priority score (0-100)
    internal func calculatePriority(
        basePriority: Int,
        for candidate: Candidate,
        strategyType: VerifierKind
    ) -> Int {
        var priority = basePriority
        
        // Boost priority if other strategies have failed
        switch strategyType {
        case .trafficEye:
            if candidate.verificationTracker.llmAttempts > 0 {
                priority += 20 // Prefer TrafficEye if LLM has failed
            }
        case .llm:
            if candidate.verificationTracker.trafficAttempts >= VerificationPolicy.minPrimaryRetries {
                priority += 30 // Prefer LLM if TrafficEye has failed multiple times
            }
            if candidate.view == .side {
                priority += 10 // LLM is better for side views
            }
        }
        
        // Reduce priority if this strategy has failed too many times
        let attempts = strategyType == .trafficEye ? 
            candidate.verificationTracker.trafficAttempts : 
            candidate.verificationTracker.llmAttempts
        
        priority -= attempts * 10
        
        return max(0, priority)
    }
}
