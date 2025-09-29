//  VerificationStrategyFactory.swift
//  thing-finder
//
//  Factory for creating and managing verification strategies. This replaces
//  the complex logic in VerifierService with a clean, configurable approach.
//
//  Created by Cascade AI.

import Foundation

/// Factory for creating and managing verification strategies.
///
/// This factory is responsible for creating and configuring all verification strategies
/// and providing a strategy manager that can select the most appropriate strategy
/// for a given candidate. It replaces the complex logic in VerifierService with a
/// clean, configurable approach.
///
/// ## Topics
///
/// ### Creating a Factory
/// - ``init(config:)``
///
/// ### Creating Strategies
/// - ``createStrategyManager(targetTextDescription:)``
/// - ``createStrategy(kind:targetTextDescription:)``
public class VerificationStrategyFactory {
    
    /// Configuration for the verification process.
    private let config: VerificationConfig
    
    /// Initializes a new verification strategy factory.
    ///
    /// - Parameter config: Configuration for the verification process
    public init(config: VerificationConfig) {
        self.config = config
    }
    
    /// Create a strategy manager with all available strategies.
    ///
    /// This method creates all available verification strategies based on the current
    /// configuration and returns a strategy manager that can select the most appropriate
    /// strategy for a given candidate.
    ///
    /// - Parameter targetTextDescription: The target description to verify against
    /// - Returns: Configured strategy manager with all available strategies
    public func createStrategyManager(targetTextDescription: String) -> VerificationStrategyManager {
        let strategies = createAllStrategies(targetTextDescription: targetTextDescription)
        return VerificationStrategyManager(strategies: strategies, config: config, targetTextDescription: targetTextDescription)
    }
    
    /// Create all available verification strategies.
    ///
    /// This method creates all verification strategies based on the current configuration.
    /// It always includes the TrafficEye strategy and conditionally includes the LLM and
    /// Advanced LLM strategies if combined verification is enabled.
    ///
    /// - Parameter targetTextDescription: The target description to verify against
    /// - Returns: Array of configured strategies
    private func createAllStrategies(targetTextDescription: String) -> [VerificationStrategy] {
        var strategies: [VerificationStrategy] = []
        
        // Always include TrafficEye strategy (fast, primary)
        strategies.append(TrafficEyeStrategy(
            targetTextDescription: targetTextDescription,
            config: config
        ))
        
        // Include LLM strategy if combined verifier is enabled
        if config.useCombinedVerifier {
            strategies.append(LLMStrategy(
                targetTextDescription: targetTextDescription,
                config: config
            ))
            
            // Include advanced LLM as fallback
            strategies.append(AdvancedLLMStrategy(
                targetTextDescription: targetTextDescription,
                config: config
            ))
        }
        
        return strategies
    }
    
    /// Create a specific strategy by type (for backwards compatibility).
    ///
    /// This method creates a specific verification strategy by type, which is useful
    /// for backwards compatibility with code that expects specific verifier types.
    ///
    /// - Parameters:
    ///   - kind: The type of verifier to create
    ///   - targetTextDescription: The target description to verify against
    /// - Returns: The requested verification strategy
    public func createStrategy(
        kind: VerifierKind,
        targetTextDescription: String
    ) -> VerificationStrategy {
        switch kind {
        case .trafficEye:
            return TrafficEyeStrategy(
                targetTextDescription: targetTextDescription,
                config: config
            )
        case .llm:
            return LLMStrategy(
                targetTextDescription: targetTextDescription,
                config: config
            )
        }
    }
}
