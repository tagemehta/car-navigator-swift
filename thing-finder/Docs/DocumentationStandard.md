# Swift Documentation Standard with DocC

## Overview

This document outlines the standard approach for documenting code in the thing-finder project using DocC (Documentation Compiler). Following these guidelines ensures consistency, improves maintainability, and makes the codebase more accessible to new developers while enabling the generation of rich, interactive documentation.

## Documentation Format

We use Swift's native documentation comments with DocC-compatible markdown formatting. Documentation comments begin with `///` for single-line comments or `/**` and `*/` for multi-line comments.

## Function Documentation

### Required Elements

Every function should include the following documentation elements:

1. **Summary**: A brief, one-line description of what the function does
2. **Discussion** (optional): Additional details about the function's behavior, edge cases, or implementation notes
3. **Parameters**: Description of each parameter
4. **Returns**: Description of the return value
5. **Throws**: Description of errors that can be thrown (if applicable)
6. **Note** (optional): Important information that doesn't fit elsewhere
7. **Warning** (optional): Critical information about potential issues

### Template

```swift
/// A brief description of what the function does.
///
/// A more detailed discussion about the function's behavior,
/// implementation details, or usage notes if needed.
///
/// - Parameters:
///   - paramName: Description of the parameter
///   - anotherParam: Description of another parameter
/// - Returns: Description of what is returned
/// - Throws: Description of errors that can be thrown
/// - Note: Any additional information
/// - Warning: Critical information about potential issues
func functionName(paramName: ParamType, anotherParam: AnotherType) throws -> ReturnType {
    // Implementation
}
```

### Example

```swift
/// Verifies if an image matches the target description.
///
/// This function analyzes the provided image and determines if it matches
/// the target description using computer vision techniques. It handles
/// various edge cases including poor lighting and partial occlusion.
///
/// - Parameters:
///   - image: The image to verify
///   - candidate: The candidate containing context for verification
/// - Returns: A publisher that emits a verification outcome
/// - Throws: `VerificationError` if verification fails
func verify(image: UIImage, candidate: Candidate) -> AnyPublisher<VerificationOutcome, Error> {
    // Implementation
}
```

## Class and Protocol Documentation

### Required Elements

Every class, struct, enum, and protocol should include:

1. **Summary**: A brief description of the type's purpose
2. **Discussion** (optional): Additional details about the type
3. **Topics** (recommended): Organize members into logical groups
4. **Note** (optional): Important information about usage

### Template

```swift
/// A brief description of the type.
///
/// A more detailed discussion about the type's purpose,
/// behavior, or implementation details if needed.
///
/// ## Topics
///
/// ### Essentials
/// - ``someProperty``
/// - ``someMethod()``
///
/// ### Advanced Usage
/// - ``anotherMethod()``
///
/// - Note: Any additional information
public class ClassName {
    // Implementation
}
```

## Property Documentation

### Required Elements

Public and internal properties should include:

1. **Summary**: A brief description of the property's purpose
2. **Note** (optional): Important information about usage

### Template

```swift
/// A brief description of the property.
/// - Note: Any additional information
public var propertyName: PropertyType
```

## Extension Documentation

Extensions should be documented with:

1. **Summary**: A brief description of what functionality the extension adds
2. **Note** (optional): Important information about the extension

### Template

```swift
/// Adds functionality related to [specific domain] to [Type].
extension Type {
    // Implementation
}
```

## MARK Comments

Use MARK comments to organize code into logical sections. These help with code organization and also influence how DocC groups methods in the documentation:

```swift
// MARK: - Initialization

// MARK: - Public Methods

// MARK: - Private Helpers

// MARK: - Protocol Conformance
```

## DocC-Specific Features

### Article Documentation

For complex topics that require more explanation, create dedicated documentation articles:

```swift
/// A brief description of the framework or module.
///
/// This is the main entry point for the documentation.
///
/// ## Overview
///
/// Provide a high-level overview of the framework.
///
/// ## Topics
///
/// ### Essentials
/// - <doc:GettingStarted>
/// - ``MainClass``
///
/// ### Advanced Topics
/// - <doc:AdvancedUsage>
/// - ``SpecializedClass``
@main
public struct MyModule {}
```

### Symbol Links

Use double backticks to link to symbols in your codebase:

- Link to a class: ``ClassName``
- Link to a method: ``ClassName/methodName()``
- Link to a property: ``ClassName/propertyName``

### Article Links

Use angle brackets to link to documentation articles:

- Link to an article: <doc:ArticleName>

## Documentation Best Practices

1. **Be Concise**: Keep descriptions brief but complete
2. **Use Present Tense**: Write "Returns the count" not "Return the count"
3. **Focus on What, Not How**: Document what a function does, not how it works (unless relevant)
4. **Document Edge Cases**: Include information about nil values, empty collections, or error conditions
5. **Use Code Formatting**: Use backticks for inline code references (e.g., `paramName`)
6. **Cross-Reference**: Link to related symbols using double backticks (e.g., ``ClassName``)
7. **Document Assumptions**: Note any assumptions the code makes about its inputs or environment
8. **Use Topics**: Organize related symbols into topic groups for better navigation
9. **Add Examples**: Include code examples to demonstrate usage

## Building Documentation

To build and view the documentation:

1. Use Xcode's Product > Build Documentation menu
2. View the documentation in Xcode's Developer Documentation window
3. For CI/CD, use the `xcodebuild docbuild` command

## Tools and Enforcement

- Use SwiftLint rules to enforce documentation standards
- Use DocC for generating and viewing documentation
- Review documentation during code reviews
- Consider automating documentation generation in CI/CD pipelines

## Example File

```swift
//  VerificationStrategy.swift
//  thing-finder
//
//  Unified verification strategy interface that simplifies the verification
//  system by providing a common interface for all verification approaches.
//
//  Created by [Author].

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
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: True if this strategy is appropriate for the candidate
    func shouldUse(for candidate: Candidate) -> Bool
    
    /// Get the priority of this strategy (higher = more preferred).
    ///
    /// - Parameter candidate: The candidate to evaluate
    /// - Returns: Priority score (0-100)
    func priority(for candidate: Candidate) -> Int
}
```
