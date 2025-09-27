//  LLMStrategy.swift
//  thing-finder
//
//  LLM verification strategy implementation that wraps the existing
//  LLMVerifier with the new strategy interface.
//
//  Created by Cascade AI.

import Combine
import Foundation
import UIKit

/// LLM verification strategy implementation.
///
/// This strategy wraps the existing LLMVerifier with the new strategy interface.
/// It serves as a secondary verification method, particularly effective for side-view
/// candidates and when the primary method has failed multiple times.
///
/// ## Topics
///
/// ### Creating an LLM Strategy
/// - ``init(targetTextDescription:config:)``
///
/// ### Strategy Selection Logic
/// - ``shouldUse(for:)``
/// - ``priority(for:)``
public class LLMStrategy: BaseVerificationStrategy {
    
    /// The underlying LLM verifier instance.
    private let llmVerifier: TwoStepVerifier
    
    /// Initializes a new LLM verification strategy.
    ///
    /// - Parameters:
    ///   - targetTextDescription: The target text description to verify against
    ///   - config: Configuration for the verification process
    public init(targetTextDescription: String, config: VerificationConfig) {
        self.llmVerifier = TwoStepVerifier(targetTextDescription: targetTextDescription)
        
        super.init(
            strategyName: "LLM",
            targetTextDescription: targetTextDescription,
            config: config
        )
    }
    
    // MARK: - Strategy Selection Logic
    
    /// Check if this strategy should be used for the given candidate.
    ///
    /// This method replicates the exact logic from the original `VerificationPolicy.nextKind()`
    /// method for LLM selection, ensuring backward compatibility with the
    /// original verification system.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: True if LLM is appropriate for the candidate
    public override func shouldUse(for candidate: Candidate) -> Bool {
        // Replicate exact VerificationPolicy.nextKind() logic for LLM
        
        // Don't use LLM if it has already failed too many times (will cycle back to TrafficEye)
        if candidate.verificationTracker.llmAttempts >= VerificationPolicy.maxLLMRetries {
            return false
        }
        
        // Use LLM when TrafficEye keeps failing (any view)
        if candidate.verificationTracker.trafficAttempts >= VerificationPolicy.maxPrimaryRetries {
            return meetsBasicRequirements(candidate)
        }
        
        // Earlier fallback for side view after fewer failures
        if candidate.view == .side && candidate.verificationTracker.trafficAttempts >= VerificationPolicy.minPrimaryRetries {
            return meetsBasicRequirements(candidate)
        }
        
        // Otherwise don't use LLM (TrafficEye should be used)
        return false
    }
    
    /// Get the priority of this strategy (higher = more preferred).
    ///
    /// LLM gets highest priority when it should be used (matches original policy escalation)
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: Priority score (0-100)
    public override func priority(for candidate: Candidate) -> Int {
        // LLM gets highest priority when it should be used (matches original policy escalation)
        return shouldUse(for: candidate) ? 90 : 0
    }
    
    // MARK: - Verification Implementation
    
    /// Perform the actual verification using LLM.
    ///
    /// This method delegates the verification to the underlying LLMVerifier instance.
    ///
    /// - Parameters:
    ///   - image: The image to verify
    ///   - candidate: The candidate being verified
    /// - Returns: Publisher that emits verification outcome
    internal override func performVerification(
        image: UIImage, 
        candidate: Candidate
    ) -> AnyPublisher<VerificationOutcome, Error> {
        return llmVerifier.verify(image: image)
    }
}
