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
      
    print(token)
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

struct ModelConstants {
  static let modelMapping = [
    "AM General Hummer SUV 2000": "am general hummer",
    "Acura RL Sedan 2012": "acura rl",
    "Acura TL Sedan 2012": "acura tl",
    "Acura TL Type-S 2008": "acura tl type-s",
    "Acura TSX Sedan 2012": "acura tsx",
    "Acura Integra Type R 2001": "acura integra type r",
    "Acura ZDX Hatchback 2012": "acura zdx",
    "Aston Martin V8 Vantage Convertible 2012": "aston martin v8 vantage",
    "Aston Martin V8 Vantage Coupe 2012": "aston martin v8 vantage",
    "Aston Martin Virage Convertible 2012": "aston martin virage",
    "Aston Martin Virage Coupe 2012": "aston martin virage",
    "Audi RS 4 Convertible 2008": "audi rs 4",
    "Audi A5 Coupe 2012": "audi a5",
    "Audi TTS Coupe 2012": "audi tts",
    "Audi R8 Coupe 2012": "audi r8",
    "Audi V8 Sedan 1994": "audi v8",
    "Audi 100 Sedan 1994": "audi 100",
    "Audi 100 Wagon 1994": "audi 100",
    "Audi TT Hatchback 2011": "audi tt",
    "Audi S6 Sedan 2011": "audi s6",
    "Audi S5 Convertible 2012": "audi s5",
    "Audi S5 Coupe 2012": "audi s5",
    "Audi S4 Sedan 2012": "audi s4",
    "Audi S4 Sedan 2007": "audi s4",
    "Audi TT RS Coupe 2012": "audi tt rs",
    "BMW ActiveHybrid 5 Sedan 2012": "bmw activehybrid 5",
    "BMW 1 Series Convertible 2012": "bmw 1 series",
    "BMW 1 Series Coupe 2012": "bmw 1 series",
    "BMW 3 Series Sedan 2012": "bmw 3 series",
    "BMW 3 Series Wagon 2012": "bmw 3 series",
    "BMW 6 Series Convertible 2007": "bmw 6 series",
    "BMW X5 SUV 2007": "bmw x5",
    "BMW X6 SUV 2012": "bmw x6",
    "BMW M3 Coupe 2012": "bmw m3",
    "BMW M5 Sedan 2010": "bmw m5",
    "BMW M6 Convertible 2010": "bmw m6",
    "BMW X3 SUV 2012": "bmw x3",
    "BMW Z4 Convertible 2012": "bmw z4",
    "Bentley Continental Supersports Conv. Convertible 2012": "bentley continental supersports",
    "Bentley Arnage Sedan 2009": "bentley arnage",
    "Bentley Mulsanne Sedan 2011": "bentley mulsanne",
    "Bentley Continental GT Coupe 2012": "bentley continental gt",
    "Bentley Continental GT Coupe 2007": "bentley continental gt",
    "Bentley Continental Flying Spur Sedan 2007": "bentley continental flying spur",
    "Bugatti Veyron 16.4 Convertible 2009": "bugatti veyron",
    "Bugatti Veyron 16.4 Coupe 2009": "bugatti veyron",
    "Buick Regal GS 2012": "buick regal",
    "Buick Rainier SUV 2007": "buick rainier",
    "Buick Verano Sedan 2012": "buick verano",
    "Buick Enclave SUV 2012": "buick enclave",
    "Cadillac CTS-V Sedan 2012": "cadillac cts-v",
    "Cadillac SRX SUV 2012": "cadillac srx",
    "Cadillac Escalade EXT Crew Cab 2007": "cadillac escalade",
    "Chevrolet Silverado 1500 Hybrid Crew Cab 2012": "chevrolet silverado 1500 hybrid",
    "Chevrolet Corvette Convertible 2012": "chevrolet corvette",
    "Chevrolet Corvette ZR1 2012": "chevrolet corvette zr1",
    "Chevrolet Corvette Ron Fellows Edition Z06 2007": "chevrolet corvette z06",
    "Chevrolet Traverse SUV 2012": "chevrolet traverse",
    "Chevrolet Camaro Convertible 2012": "chevrolet camaro",
    "Chevrolet HHR SS 2010": "chevrolet hhr",
    "Chevrolet Impala Sedan 2007": "chevrolet impala",
    "Chevrolet Tahoe Hybrid SUV 2012": "chevrolet tahoe hybrid",
    "Chevrolet Sonic Sedan 2012": "chevrolet sonic",
    "Chevrolet Express Cargo Van 2007": "chevrolet express",
    "Chevrolet Avalanche Crew Cab 2012": "chevrolet avalanche",
    "Chevrolet Cobalt SS 2010": "chevrolet cobalt",
    "Chevrolet Malibu Hybrid Sedan 2010": "chevrolet malibu hybrid",
    "Chevrolet TrailBlazer SS 2009": "chevrolet trailblazer",
    "Chevrolet Silverado 2500HD Regular Cab 2012": "chevrolet silverado 2500hd",
    "Chevrolet Silverado 1500 Classic Extended Cab 2007": "chevrolet silverado 1500",
    "Chevrolet Express Van 2007": "chevrolet express",
    "Chevrolet Monte Carlo Coupe 2007": "chevrolet monte carlo",
    "Chevrolet Malibu Sedan 2007": "chevrolet malibu",
    "Chevrolet Silverado 1500 Extended Cab 2012": "chevrolet silverado 1500",
    "Chevrolet Silverado 1500 Regular Cab 2012": "chevrolet silverado 1500",
    "Chrysler Aspen SUV 2009": "chrysler aspen",
    "Chrysler Sebring Convertible 2010": "chrysler sebring",
    "Chrysler Town and Country Minivan 2012": "chrysler town and country",
    "Chrysler 300 SRT-8 2010": "chrysler 300",
    "Chrysler Crossfire Convertible 2008": "chrysler crossfire",
    "Chrysler PT Cruiser Convertible 2008": "chrysler pt cruiser",
    "Daewoo Nubira Wagon 2002": "daewoo nubira",
    "Dodge Caliber Wagon 2012": "dodge caliber",
    "Dodge Caliber Wagon 2007": "dodge caliber",
    "Dodge Caravan Minivan 1997": "dodge caravan",
    "Dodge Ram Pickup 3500 Crew Cab 2010": "dodge ram 3500",
    "Dodge Ram Pickup 3500 Quad Cab 2009": "dodge ram 3500",
    "Dodge Sprinter Cargo Van 2009": "dodge sprinter",
    "Dodge Journey SUV 2012": "dodge journey",
    "Dodge Dakota Crew Cab 2010": "dodge dakota",
    "Dodge Dakota Club Cab 2007": "dodge dakota",
    "Dodge Magnum Wagon 2008": "dodge magnum",
    "Dodge Challenger SRT8 2011": "dodge challenger",
    "Dodge Durango SUV 2012": "dodge durango",
    "Dodge Durango SUV 2007": "dodge durango",
    "Dodge Charger Sedan 2012": "dodge charger",
    "Dodge Charger SRT-8 2009": "dodge charger",
    "Eagle Talon Hatchback 1998": "eagle talon",
    "FIAT 500 Abarth 2012": "fiat 500",
    "FIAT 500 Convertible 2012": "fiat 500",
    "Ferrari FF Coupe 2012": "ferrari ff",
    "Ferrari California Convertible 2012": "ferrari california",
    "Ferrari 458 Italia Convertible 2012": "ferrari 458 italia",
    "Ferrari 458 Italia Coupe 2012": "ferrari 458 italia",
    "Fisker Karma Sedan 2012": "fisker karma",
    "Ford F-450 Super Duty Crew Cab 2012": "ford f-450 super duty",
    "Ford Mustang Convertible 2007": "ford mustang",
    "Ford Freestar Minivan 2007": "ford freestar",
    "Ford Expedition EL SUV 2009": "ford expedition",
    "Ford Edge SUV 2012": "ford edge",
    "Ford Ranger SuperCab 2011": "ford ranger",
    "Ford GT Coupe 2006": "ford gt",
    "Ford F-150 Regular Cab 2012": "ford f-150",
    "Ford F-150 Regular Cab 2007": "ford f-150",
    "Ford Focus Sedan 2007": "ford focus",
    "Ford E-Series Wagon Van 2012": "ford e-series wagon",
    "Ford Fiesta Sedan 2012": "ford fiesta",
    "GMC Terrain SUV 2012": "gmc terrain",
    "GMC Savana Van 2012": "gmc savana",
    "GMC Yukon Hybrid SUV 2012": "gmc yukon hybrid",
    "GMC Acadia SUV 2012": "gmc acadia",
    "GMC Canyon Extended Cab 2012": "gmc canyon",
    "Geo Metro Convertible 1993": "geo metro",
    "HUMMER H3T Crew Cab 2010": "hummer h3t",
    "HUMMER H2 SUT Crew Cab 2009": "hummer h2 sut",
    "Honda Odyssey Minivan 2012": "honda odyssey",
    "Honda Odyssey Minivan 2007": "honda odyssey",
    "Honda Accord Coupe 2012": "honda accord",
    "Honda Accord Sedan 2012": "honda accord",
    "Hyundai Veloster Hatchback 2012": "hyundai veloster",
    "Hyundai Santa Fe SUV 2012": "hyundai santa fe",
    "Hyundai Tucson SUV 2012": "hyundai tucson",
    "Hyundai Veracruz SUV 2012": "hyundai veracruz",
    "Hyundai Sonata Hybrid Sedan 2012": "hyundai sonata hybrid",
    "Hyundai Elantra Sedan 2007": "hyundai elantra",
    "Hyundai Accent Sedan 2012": "hyundai accent",
    "Hyundai Genesis Sedan 2012": "hyundai genesis",
    "Hyundai Sonata Sedan 2012": "hyundai sonata",
    "Hyundai Elantra Touring Hatchback 2012": "hyundai elantra touring",
    "Hyundai Azera Sedan 2012": "hyundai azera",
    "Infiniti G Coupe IPL 2012": "infiniti g ipl",
    "Infiniti QX56 SUV 2011": "infiniti qx56",
    "Isuzu Ascender SUV 2008": "isuzu ascender",
    "Jaguar XK XKR 2012": "jaguar xk",
    "Jeep Patriot SUV 2012": "jeep patriot",
    "Jeep Wrangler SUV 2012": "jeep wrangler",
    "Jeep Liberty SUV 2012": "jeep liberty",
    "Jeep Grand Cherokee SUV 2012": "jeep grand cherokee",
    "Jeep Compass SUV 2012": "jeep compass",
    "Lamborghini Reventon Coupe 2008": "lamborghini reventon",
    "Lamborghini Aventador Coupe 2012": "lamborghini aventador",
    "Lamborghini Gallardo LP 570-4 Superleggera 2012": "lamborghini gallardo",
    "Lamborghini Diablo Coupe 2001": "lamborghini diablo",
    "Land Rover Range Rover SUV 2012": "land rover range rover",
    "Land Rover LR2 SUV 2012": "land rover lr2",
    "Lincoln Town Car Sedan 2011": "lincoln town car",
    "MINI Cooper Roadster Convertible 2012": "mini cooper roadster",
    "Maybach Landaulet Convertible 2012": "maybach landaulet",
    "Mazda Tribute SUV 2011": "mazda tribute",
    "McLaren MP4-12C Coupe 2012": "mclaren mp4-12c",
    "Mercedes-Benz 300-Class Convertible 1993": "mercedes-benz 300-class",
    "Mercedes-Benz C-Class Sedan 2012": "mercedes-benz c-class",
    "Mercedes-Benz SL-Class Coupe 2009": "mercedes-benz sl-class",
    "Mercedes-Benz E-Class Sedan 2012": "mercedes-benz e-class",
    "Mercedes-Benz S-Class Sedan 2012": "mercedes-benz s-class",
    "Mercedes-Benz Sprinter Van 2012": "mercedes-benz sprinter",
    "Mitsubishi Lancer Sedan 2012": "mitsubishi lancer",
    "Nissan Leaf Hatchback 2012": "nissan leaf",
    "Nissan NV Passenger Van 2012": "nissan nv passenger",
    "Nissan Juke Hatchback 2012": "nissan juke",
    "Nissan 240SX Coupe 1998": "nissan 240sx",
    "Plymouth Neon Coupe 1999": "plymouth neon",
    "Porsche Panamera Sedan 2012": "porsche panamera",
    "Ram C/V Cargo Van Minivan 2012": "ram c/v",
    "Rolls-Royce Phantom Drophead Coupe Convertible 2012": "rolls-royce phantom drophead",
    "Spyker C8 Convertible 2009": "spyker c8",
    "Suzuki Aerio Sedan 2007": "suzuki aerio",
    "Suzuki Kizashi Sedan 2012": "suzuki kizashi",
    "Suzuki SX4 Hatchback 2012": "suzuki sx4",
    "Suzuki SX4 Sedan 2012": "suzuki sx4",
    "Suzuki SX4 Wagon 2008": "suzuki sx4",
    "Tesla Model S Sedan 2012": "tesla model s",
    "Toyota Sequoia SUV 2012": "toyota sequoia",
    "Toyota Camry Sedan 2012": "toyota camry",
    "Toyota Corolla Sedan 2012": "toyota corolla",
    "Toyota 4Runner SUV 2012": "toyota 4runner",
    "Volkswagen Golf Hatchback 2012": "volkswagen golf",
    "Volvo C30 Hatchback 2012": "volvo c30",
    "Volvo XC90 SUV 2007": "volvo xc90",
  ]

  static let modelValues = modelMapping.values

}
