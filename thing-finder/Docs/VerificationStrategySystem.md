# Verification Strategy System

## Overview

The Verification Strategy System implements a clean, modular approach to verifying candidates in the thing-finder pipeline. It uses the Strategy design pattern to encapsulate different verification methods, allowing for dynamic selection of the most appropriate verification approach based on the candidate's characteristics and verification history.

## Architecture

The system consists of the following components:

### Core Components

1. **VerificationStrategy Protocol**
   - Defines the common interface for all verification strategies
   - Provides methods for verification, strategy selection, and priority calculation

2. **BaseVerificationStrategy**
   - Abstract base class implementing common functionality
   - Handles error processing, timeout management, and retry logic
   - Provides helper methods for strategy selection

3. **VerificationStrategyManager**
   - Manages strategy selection and execution
   - Handles counter resets when switching between strategies
   - Provides a unified verification interface

4. **VerificationStrategyFactory**
   - Creates and configures all available strategies
   - Provides a clean way to instantiate the strategy system

### Concrete Strategies

1. **TrafficEyeStrategy**
   - Fast, primary verification method
   - Wraps the existing TrafficEyeVerifier
   - Prioritized for front-view candidates and initial verification attempts

2. **LLMStrategy**
   - More accurate but slower verification method
   - Wraps the existing TwoStepVerifier
   - Prioritized for side-view candidates and after TrafficEye failures

3. **AdvancedLLMStrategy**
   - Last-resort verification method
   - Wraps the existing AdvancedLLMVerifier
   - Used when both TrafficEye and regular LLM have failed

## Strategy Selection Logic

The system dynamically selects the most appropriate strategy based on:

1. **Candidate View**
   - Side views are more likely to use LLM strategies
   - Front views prefer TrafficEye for speed

2. **Verification History**
   - Tracks attempts for each strategy type
   - Switches strategies after a configurable number of failures
   - Resets counters when switching strategies

3. **Priority Calculation**
   - Each strategy calculates its priority for a given candidate
   - Higher priority strategies are selected first
   - Priorities adjust based on previous verification attempts

## Verification Flow

1. The `VerifierService` requests verification from the `VerificationStrategyManager`
2. The manager selects the best strategy based on priority and suitability
3. The selected strategy performs verification and returns an outcome
4. Attempt counters are updated and opposite counters are reset when switching strategies
5. If verification fails, the next best strategy is selected on the next attempt

## Error Handling

The system provides robust error handling:

1. **TwoStepError Handling**
   - Converts specific errors to appropriate rejection reasons
   - Preserves error context for debugging

2. **Timeout Management**
   - Enforces timeouts to prevent hanging verifications
   - Converts timeouts to appropriate rejection outcomes

3. **Strategy Selection Failures**
   - Handles cases where no suitable strategy is found
   - Provides clear error messages for debugging

## Integration with Existing System

The verification strategy system integrates with the existing pipeline through:

1. **VerifierService**
   - Uses the strategy manager for all verifications
   - Maintains backward compatibility with existing code

2. **Candidate Store**
   - Updates verification attempt counters
   - Tracks verification history for strategy selection

## Configuration

The system is configurable through:

1. **VerificationConfig**
   - Controls whether to use combined verification
   - Configures strategy-specific parameters

2. **VerificationPolicy**
   - Defines retry limits and thresholds
   - Controls when to switch between strategies

## Benefits

1. **Modularity**
   - Each strategy is self-contained and focused
   - Easy to add new strategies without modifying existing code

2. **Maintainability**
   - Clear separation of concerns
   - Reduced complexity in the VerifierService

3. **Testability**
   - Each strategy can be tested independently
   - Strategy selection logic is explicit and testable

4. **Flexibility**
   - Easy to adjust strategy selection logic
   - Simple to add or remove strategies as needed
