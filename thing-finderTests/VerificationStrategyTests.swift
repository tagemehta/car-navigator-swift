//
//  VerificationStrategyTests.swift
//  thing-finder
//
//  Created by Sam Mehta on 9/4/25.
//


//  VerificationStrategyTests.swift
//  thing-finderTests
//
//  XCTest suite for the verification strategy system.
//
//  Created by Cascade AI.

import XCTest
import Foundation
import UIKit
import Vision
@testable import thing_finder

class VerificationStrategyTests: XCTestCase {
    
    // MARK: - Test Setup
    
    override func setUp() {
        super.setUp()
        // Setup code that runs before each test
    }
    
    override func tearDown() {
        // Cleanup code that runs after each test
        super.tearDown()
    }
    
    // MARK: - Strategy Factory Tests
    
    func testStrategyFactory() {
        // Given
        let config = VerificationConfig(expectedPlate: "ABC123")
        let factory = VerificationStrategyFactory(config: config)
        
        // When
        let manager = factory.createStrategyManager(targetTextDescription: "red Toyota Camry")
        
        // Then
        XCTAssertFalse(manager.strategies.isEmpty, "Strategy manager should have strategies")
    }
    
    // MARK: - Strategy Selection Tests
    
    func testInitialStrategySelection() {
        // Given
        var config = VerificationConfig(expectedPlate: "ABC123")
        config.useCombinedVerifier = true
        let factory = VerificationStrategyFactory(config: config)
        let manager = factory.createStrategyManager(targetTextDescription: "red Toyota Camry")
        
        // Create a test candidate
        let trackingRequest = VNTrackObjectRequest()
        let candidate = Candidate(
            trackingRequest: trackingRequest,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        )
        
        // When
        let initialStrategy = manager.selectStrategy(for: candidate)
        let originalInitial = VerificationPolicy.nextKind(for: candidate)
        
        // Then
        XCTAssertEqual(initialStrategy?.strategyName, "TrafficEye", "Should initially select TrafficEye")
        XCTAssertEqual(originalInitial, .trafficEye, "Original policy should also select TrafficEye")
    }
    
    func testSideViewEscalation() {
        // Given
        var config = VerificationConfig(expectedPlate: "ABC123")
        config.useCombinedVerifier = true
        let factory = VerificationStrategyFactory(config: config)
        let manager = factory.createStrategyManager(targetTextDescription: "red Toyota Camry")
        
        // Create a test candidate
        let trackingRequest = VNTrackObjectRequest()
        var candidate = Candidate(
            trackingRequest: trackingRequest,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        )
        
        // When
        candidate.view = .side
        candidate.verificationTracker.trafficAttempts = VerificationPolicy.minPrimaryRetries
        let sideStrategy = manager.selectStrategy(for: candidate)
        let originalSide = VerificationPolicy.nextKind(for: candidate)
        
        // Then
        XCTAssertEqual(sideStrategy?.strategyName, "LLM", "Should escalate to LLM for side view")
        XCTAssertEqual(originalSide, .llm, "Original policy should also escalate to LLM")
    }
    
    func testGeneralEscalation() {
        // Given
        var config = VerificationConfig(expectedPlate: "ABC123")
        config.useCombinedVerifier = true
        let factory = VerificationStrategyFactory(config: config)
        let manager = factory.createStrategyManager(targetTextDescription: "red Toyota Camry")
        
        // Create a test candidate
        let trackingRequest = VNTrackObjectRequest()
        var candidate = Candidate(
            trackingRequest: trackingRequest,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        )
        
        // When
        candidate.view = .front
        candidate.verificationTracker.trafficAttempts = VerificationPolicy.maxPrimaryRetries
        let escalatedStrategy = manager.selectStrategy(for: candidate)
        let originalEscalated = VerificationPolicy.nextKind(for: candidate)
        
        // Then
        XCTAssertEqual(escalatedStrategy?.strategyName, "LLM", "Should escalate to LLM after max failures")
        XCTAssertEqual(originalEscalated, .llm, "Original policy should also escalate to LLM")
    }
    
    func testCycleBackToTrafficEye() {
        // Given
        var config = VerificationConfig(expectedPlate: "ABC123")
        config.useCombinedVerifier = true
        let factory = VerificationStrategyFactory(config: config)
        let manager = factory.createStrategyManager(targetTextDescription: "red Toyota Camry")
        
        // Create a test candidate
        let trackingRequest = VNTrackObjectRequest()
        var candidate = Candidate(
            trackingRequest: trackingRequest,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        )
        
        // When
        candidate.verificationTracker.trafficAttempts = VerificationPolicy.maxPrimaryRetries
        candidate.verificationTracker.llmAttempts = VerificationPolicy.maxLLMRetries
        let cycleBackStrategy = manager.selectStrategy(for: candidate)
        let originalCycleBack = VerificationPolicy.nextKind(for: candidate)
        
        // Then
        XCTAssertEqual(cycleBackStrategy?.strategyName, "TrafficEye", "Should cycle back to TrafficEye")
        XCTAssertEqual(originalCycleBack, .trafficEye, "Original policy should also cycle back")
    }
    
    // MARK: - Strategy Priority Tests
    
    func testStrategyPriorities() {
        // Given
        let config = VerificationConfig(expectedPlate: "ABC123")
        let trafficEyeStrategy = TrafficEyeStrategy(targetTextDescription: "test", config: config)
        let llmStrategy = LLMStrategy(targetTextDescription: "test", config: config)
        
        let trackingRequest = VNTrackObjectRequest()
        let candidate = Candidate(
            trackingRequest: trackingRequest,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        )
        
        // When
        let trafficEyePriority = trafficEyeStrategy.priority(for: candidate)
        let llmPriority = llmStrategy.priority(for: candidate)
        
        // Then
        XCTAssertGreaterThan(trafficEyePriority, llmPriority, "TrafficEye should have higher initial priority")
    }
}

// Extension to make VNTrackObjectRequest initializable for testing
extension VNTrackObjectRequest {
    convenience init() {
        // Create a dummy observation for testing
        let observation = VNDetectedObjectObservation(boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))
        self.init(detectedObjectObservation: observation)
    }
}
