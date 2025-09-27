//  AdvancedLLMStrategy.swift
//  thing-finder
//
//  Advanced LLM verification strategy implementation that wraps the existing
//  AdvancedLLMVerifier with the new strategy interface.
//
//  Created by Cascade AI.

import Combine
import Foundation
import UIKit

/// Advanced LLM verification strategy implementation.
///
/// This strategy wraps the existing AdvancedLLMVerifier with the new strategy interface.
/// It serves as a last-resort verification method when other strategies have failed
/// or are not suitable for the candidate.
///
/// ## Topics
///
/// ### Creating an Advanced LLM Strategy
/// - ``init(targetTextDescription:config:)``
///
/// ### Strategy Selection Logic
/// - ``shouldUse(for:)``
/// - ``priority(for:)``
public class AdvancedLLMStrategy: BaseVerificationStrategy {
    
    /// The underlying Advanced LLM verifier instance.
    private let advancedLLMVerifier: AdvancedLLMVerifier
    
    /// Initializes a new Advanced LLM verification strategy.
    ///
    /// - Parameters:
    ///   - targetTextDescription: The target text description to verify against
    ///   - config: Configuration for the verification process
    public init(targetTextDescription: String, config: VerificationConfig) {
        self.advancedLLMVerifier = AdvancedLLMVerifier(
            targetTextDescription: targetTextDescription
        )
        
        super.init(
            strategyName: "AdvancedLLM",
            targetTextDescription: targetTextDescription,
            config: config
        )
    }
    
    // MARK: - Strategy Selection Logic
    
    /// Check if this strategy should be used for the given candidate.
    ///
    /// This strategy is designed as a fallback option and can be used for any candidate
    /// that meets basic requirements, but with a very low priority so it's only selected
    /// when other strategies are not suitable.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: True only if the candidate meets basic requirements
    public override func shouldUse(for candidate: Candidate) -> Bool {
        // Only use advanced LLM as a last resort when both TrafficEye and regular LLM have failed
        let trafficEyeExhausted = candidate.verificationTracker.trafficAttempts >= VerificationPolicy.maxPrimaryRetries
        let llmExhausted = candidate.verificationTracker.llmAttempts >= VerificationPolicy.maxLLMRetries
        
        // Use advanced LLM when both other strategies have been tried
        if !trafficEyeExhausted || !llmExhausted {
            return false
        }
        
        return meetsBasicRequirements(candidate)
    }
    
    /// Get the priority of this strategy (higher = more preferred).
    ///
    /// Advanced LLM has a lower priority (30) to ensure it's only used
    /// when other strategies are not suitable.
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: Priority score (30)
    public override func priority(for candidate: Candidate) -> Int {
        let basePriority = 30 // Lower priority - use as last resort
        return calculatePriority(
            basePriority: basePriority,
            for: candidate,
            strategyType: .llm
        )
    }
    
    // MARK: - Verification Implementation
    
    /// Perform the actual verification using Advanced LLM.
    ///
    /// This method delegates the verification to the underlying AdvancedLLMVerifier instance.
    ///
    /// - Parameters:
    ///   - image: The image to verify
    ///   - candidate: The candidate being verified
    /// - Returns: Publisher that emits verification outcome
    internal override func performVerification(
        image: UIImage,
        candidate: Candidate
    ) -> AnyPublisher<VerificationOutcome, Error> {
        return advancedLLMVerifier.verify(image: image, candidateId: candidate.id)
    }
}
