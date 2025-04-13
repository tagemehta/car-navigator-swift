//
//  Helpers.swift
//  YOLO
//
//  Created by Sam Mehta on 12/7/24.
//  Copyright © 2024 Ultralytics. All rights reserved.
//
import CoreGraphics
import CoreMedia
import Foundation
import UIKit
import Vision

// Import Car struct if it's in a different file
// If Car is defined in another file, make sure it's properly imported

// Define a structured response type for the car matching results
struct CarMatchResult {
  let car: Car  // This references the Car struct defined elsewhere in the project
  let isMatch: Bool
  let confidence: Double
}

extension ViewController {
  func intersectionOverUnion(rect1: CGRect, rect2: CGRect) -> CGFloat {
    // Calculate the intersection rectangle
    let intersection = rect1.intersection(rect2)

    // Check if there's no intersection
    if intersection.isNull {
      return 0.0
    }

    // Calculate the areas of the rectangles
    let intersectionArea = intersection.width * intersection.height
    let rect1Area = rect1.width * rect1.height
    let rect2Area = rect2.width * rect2.height

    // Calculate the union area
    let unionArea = rect1Area + rect2Area - intersectionArea

    // Calculate IoU
    return intersectionArea / unionArea
  }

  // Async function to send a single car to GPT and get a structured result
  func sendCarToGPT(car: Car, carDescription: String) async throws -> CarMatchResult {
    let uiImage = UIImage(cgImage: car.image)
    guard let imageData = uiImage.jpegData(compressionQuality: 0.8) else {
      throw NSError(
        domain: "ImageConversionError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to convert CGImage to JPEG data"])
    }

    // Encode Data to Base64 String
    let base64ImageString = imageData.base64EncodedString()

    // Create JSON Payload
    let jsonPayload: [String: Any] = [
      "model": "gpt-4o",
      "messages": [
        [
          "role": "system",
          "content": [
            [
              "type": "text",
              "text":
                "You are an AI assistant that determines if a car in an image matches the given description. Respond strictly in JSON format as per the provided schema.",
            ]
          ],
        ],
        [
          "role": "user",
          "content": [
            [
              "type": "text",
              "text":
                "Does this image contain a car that matches the following description? \(carDescription)",
            ],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64ImageString)"]],
          ],
        ],
      ],
      "functions": [
        [
          "name": "check_car_match",
          "description": "Determines if the image contains the specified car.",
          "parameters": [
            "type": "object",
            "properties": [
              "match": [
                "type": "boolean",
                "description": "Indicates if the image contains the specified car.",
              ],
              "confidence": [
                "type": "number",
                "description": "Confidence level of the match (0.0 to 1.0).",
              ],
            ],
            "required": ["match", "confidence"],
          ],
        ]
      ],
      "response_format": ["type": "json_object"],
      "max_tokens": 50,
    ]

    // Make HTTP POST Request
    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
      throw NSError(
        domain: "URLError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      
    let token = Bundle.main.infoDictionary?["GPT_APIKEY_BEARER"] as? String ?? ""
      
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])
    request.httpBody = jsonData
      
    // Use URLSession with async/await
    let (data, _) = try await URLSession.shared.data(for: request)
      
    // Parse the response
    let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
      
    // Extract the match result
    guard let choices = jsonResponse?["choices"] as? [[String: Any]],
      let firstChoice = choices.first,
      let message = firstChoice["message"] as? [String: Any],
      let functionCall = message["function_call"] as? [String: Any],
      let arguments = functionCall["arguments"] as? String,
      let argumentsData = arguments.data(using: .utf8),
      let parsedArguments = try? JSONSerialization.jsonObject(with: argumentsData, options: [])
        as? [String: Any],
      let match = parsedArguments["match"] as? Bool
    else {

      throw NSError(
        domain: "ResponseParsingError", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Failed to parse match result from response"])
    }

    // Extract confidence with a default value if not present
    let confidence = parsedArguments["confidence"] as? Double ?? 0.5

    return CarMatchResult(car: car, isMatch: match, confidence: confidence)
  }

  // Function to process multiple cars in parallel and return structured results
  func sendCarsToGPT(cars: [Car], carDescription: String) async -> [CarMatchResult] {
    // Use Task group to handle multiple concurrent requests
    return await withTaskGroup(of: CarMatchResult?.self) { group in
      for car in cars {
        group.addTask {
          do {
            return try await self.sendCarToGPT(car: car, carDescription: carDescription)
          } catch {
            print("Error processing car \(car.id): \(error.localizedDescription)")
            return nil
          }
        }
      }

      // Collect results
      var results: [CarMatchResult] = []
      for await result in group {
        if let result = result {
          results.append(result)
        }
      }

      return results
    }
  }

  // Wrapper function that can be called from non-async contexts
  func processCarsWithGPT(
    cars: [Car], carDescription: String, completion: @escaping ([CarMatchResult]) -> Void
  ) {
    Task {
      let results = await sendCarsToGPT(cars: cars, carDescription: carDescription)
      DispatchQueue.main.async {
        completion(results)
      }
    }
  }
}

extension InputViewController{
    // Async function to send a single car to GPT and get a structured result
    func sendImgToGPT(img: UIImage) async throws -> String {
      guard let imageData = img.jpegData(compressionQuality: 0.8) else {
        throw NSError(
          domain: "ImageConversionError", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to convert CGImage to JPEG data"])
      }

      // Encode Data to Base64 String
      let base64ImageString = imageData.base64EncodedString()

      // Create JSON Payload
      let jsonPayload: [String: Any] = [
        "model": "gpt-4o",
        "messages": [
          [
            "role": "system",
            "content": [
              [
                "type": "text",
                "text":
                  "You are an AI assistant that determines the type of car that fills a majority of the image. Respond strictly in JSON format as per the provided schema.",
              ]
            ],
          ],
          [
            "role": "user",
            "content": [
              [
                "type": "text",
                "text":
                  "What is the make, model, and color of the car most prominent in the input image?",
              ],
              ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64ImageString)"]],
            ],
          ],
        ],
        "functions": [
            [
              "name": "detect_car_details",
              "description": "Determines the make, model, and color of the car from the image.",
              "parameters": [
                "type": "object",
                "properties": [
                  "make": [
                    "type": "string",
                    "description": "The make of the car, e.g., Toyota."
                  ],
                  "model": [
                    "type": "string",
                    "description": "The model of the car, e.g., Camry."
                  ],
                  "color": [
                    "type": "string",
                    "description": "The color of the car, e.g., Black."
                  ]
                ],
                "required": ["make", "model", "color"]
              ]
            ]
          ],
        "response_format": ["type": "json_object"],
        "max_tokens": 50,
      ]

      // Make HTTP POST Request
      guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
        throw NSError(
          domain: "URLError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
      let token = Bundle.main.infoDictionary?["GPT_APIKEY_BEARER"] as? String ?? ""
        
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])
      request.httpBody = jsonData
        
      // Use URLSession with async/await
      let (data, _) = try await URLSession.shared.data(for: request)
        
      // Parse the response
      let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        
      // Extract the match result
      guard let choices = jsonResponse?["choices"] as? [[String: Any]],
        let firstChoice = choices.first,
        let message = firstChoice["message"] as? [String: Any],
        let functionCall = message["function_call"] as? [String: Any],
        let arguments = functionCall["arguments"] as? String,
        let argumentsData = arguments.data(using: .utf8),
        let parsedArguments = try? JSONSerialization.jsonObject(with: argumentsData, options: [])
          as? [String: Any],
        let make = parsedArguments["make"] as? String,
        let model = parsedArguments["model"] as? String,
        let color = parsedArguments["color"] as? String else {

        throw NSError(
          domain: "ResponseParsingError", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Failed to parse match result from response"])
      }

      // Extract confidence with a default value if not present
      let confidence = parsedArguments["confidence"] as? Double ?? 0.5

      return "We have detected a \(color), \(make) \(model)"
    }
}
