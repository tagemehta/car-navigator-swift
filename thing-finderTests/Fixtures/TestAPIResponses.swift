//  TestAPIResponses.swift
//  thing-finderTests
//
//  Pre-configured API response fixtures for testing verification services.
//  Contains sample responses for TrafficEye and OpenAI APIs.

import Foundation

/// Test fixtures for API responses used in verification tests.
enum TestAPIResponses {

  // MARK: - TrafficEye Responses

  /// Successful TrafficEye response with high-confidence MMR data.
  static let trafficEyeSuccess = """
    {
      "data": {
        "combinations": [{
          "roadUsers": [{
            "mmr": {
              "make": {"value": "Honda", "score": 0.95},
              "model": {"value": "Civic", "score": 0.92},
              "color": {"value": "BLUE", "score": 0.98},
              "view": {"value": "frontal", "score": 0.88}
            },
            "plates": [{
              "text": {"value": "ABC1234", "score": 0.96}
            }]
          }]
        }]
      }
    }
    """

  /// TrafficEye response with high confidence but different vehicle (for LLM mismatch test).
  static let trafficEyeMediumConfidence = """
    {
      "data": {
        "combinations": [{
          "roadUsers": [{
            "mmr": {
              "make": {"value": "Toyota", "score": 0.92},
              "model": {"value": "Camry", "score": 0.88},
              "color": {"value": "GRAY", "score": 0.95},
              "view": {"value": "side", "score": 0.85}
            },
            "plates": []
          }]
        }]
      }
    }
    """

  /// TrafficEye response with low confidence (insufficient info).
  static let trafficEyeLowConfidence = """
    {
      "data": {
        "combinations": [{
          "roadUsers": [{
            "mmr": {
              "make": {"value": "Unknown", "score": 0.30},
              "model": {"value": "Unknown", "score": 0.25},
              "color": {"value": "BLACK", "score": 0.35},
              "view": {"value": "rear", "score": 0.40}
            },
            "plates": []
          }]
        }]
      }
    }
    """

  /// TrafficEye response with no vehicle detected.
  static let trafficEyeNoVehicle = """
    {
      "data": {
        "combinations": []
      }
    }
    """

  /// TrafficEye response with plate but no MMR.
  static let trafficEyePlateOnly = """
    {
      "data": {
        "combinations": [{
          "roadUsers": [{
            "plates": [{
              "text": {"value": "XYZ9876", "score": 0.92}
            }]
          }]
        }]
      }
    }
    """

  /// TrafficEye response with rear view (good for plate detection).
  static let trafficEyeRearView = """
    {
      "data": {
        "combinations": [{
          "roadUsers": [{
            "mmr": {
              "make": {"value": "Ford", "score": 0.88},
              "model": {"value": "F-150", "score": 0.85},
              "color": {"value": "RED", "score": 0.92},
              "view": {"value": "rear", "score": 0.95}
            },
            "plates": [{
              "text": {"value": "TRUCK123", "score": 0.98}
            }]
          }]
        }]
      }
    }
    """

  // MARK: - OpenAI LLM Responses

  /// OpenAI response indicating a match.
  static let openAIMatch = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_match_decision",
              "arguments": "{\\"probability_match\\": 0.92, \\"semantic_reason\\": \\"match\\"}"
            }
          }]
        }
      }]
    }
    """

  /// OpenAI response indicating a mismatch.
  static let openAIMismatch = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_match_decision",
              "arguments": "{\\"probability_match\\": 0.15, \\"semantic_reason\\": \\"mismatch\\"}"
            }
          }]
        }
      }]
    }
    """

  /// OpenAI response indicating uncertainty (maybe).
  static let openAIMaybe = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_match_decision",
              "arguments": "{\\"probability_match\\": 0.55, \\"semantic_reason\\": \\"maybe\\"}"
            }
          }]
        }
      }]
    }
    """

  /// OpenAI response with no tool call (error case).
  static let openAINoToolCall = """
    {
      "choices": [{
        "message": {
          "content": "I cannot determine if this is a match."
        }
      }]
    }
    """

  /// OpenAI response with malformed arguments.
  static let openAIMalformed = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_match_decision",
              "arguments": "invalid json"
            }
          }]
        }
      }]
    }
    """

  // MARK: - TwoStepVerifier Responses

  /// TwoStepVerifier step 1: Vehicle info extraction.
  static let twoStepExtraction = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_vehicle_info",
              "arguments": "{\\"make\\": \\"Honda\\", \\"model\\": \\"Accord\\", \\"color\\": \\"silver\\", \\"visible_fraction\\": 0.85}"
            }
          }]
        }
      }]
    }
    """

  /// TwoStepVerifier step 2: Match confirmation.
  static let twoStepMatchConfirm = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_match_result",
              "arguments": "{\\"is_match\\": true, \\"confidence\\": 0.88, \\"reason\\": \\"Make, model, and color all match the description\\"}"
            }
          }]
        }
      }]
    }
    """

  /// TwoStepVerifier: Vehicle occluded response.
  static let twoStepOccluded = """
    {
      "choices": [{
        "message": {
          "tool_calls": [{
            "function": {
              "name": "submit_vehicle_info",
              "arguments": "{\\"make\\": \\"unknown\\", \\"model\\": \\"unknown\\", \\"color\\": \\"unknown\\", \\"visible_fraction\\": 0.25}"
            }
          }]
        }
      }]
    }
    """

  // MARK: - Helper Methods

  /// Returns response data for a given fixture.
  static func data(for fixture: String) -> Data {
    return fixture.data(using: .utf8)!
  }
}
