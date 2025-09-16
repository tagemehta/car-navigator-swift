//  TwoStepVerifier.swift

//
//  Two-step LLM verifier that first extracts make & model without bias, then
//  optionally confirms via the existing `match_object` tool.  Comparing the
//  tool-call output against the user-supplied / annotation description is done
//  locally to avoid biasing the LLM.
//
//  Created by Cascade AI on 2025-07-22.

import Combine
import Foundation
import UIKit

public final class AdvancedLLMVerifier: ImageVerifier {
  // MARK: - ImageVerifier conformance
  public let targetClasses: [String] = ["vehicle"]
  public let targetTextDescription: String

  // MARK: - Private
  private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
  private let apiKey = Bundle.main.infoDictionary?["OPENAI_API"] as? String ?? ""
  private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted]
    return e
  }()
  private let decoder = JSONDecoder()
  private var lastVerifiedDate = Date()

  // Similarity threshold (Jaccard) to decide if step-2 confirmation is needed
  private let similarityThreshold: Double = 0.6
  private let confidenceThreshold: Double = 0.86

  public init(targetTextDescription: String) { self.targetTextDescription = targetTextDescription }

  // MARK: - Tool schemas (reuse struct types from LLMVerifier)
  // Combined tool schema: extract + match fields
  private static let combinedToolSchema: Tool = Tool(
    function: Function(
      name: "extract_and_match_vehicle",
      description:
        "First, extract the vehicle's make, model, and colour from the user provided image. Then, determine if the image matches the given description, providing match, confidence, reason, and a short description. Respond with all fields in a single tool call.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "make": FunctionProperty(type: "string", description: "Vehicle manufacturer"),
          "model": FunctionProperty(type: "string", description: "Specific model of the vehicle"),
          "colour": FunctionProperty(type: "string", description: "Dominant colour of the vehicle"),
          "extract_confidence": FunctionProperty(
            type: "number",
            description: "Confidence that your make/model/colour match the user image 0-1"),
          "match": FunctionProperty(
            type: "boolean", description: "Does the image match the system description?"),
          "match_confidence": FunctionProperty(
            type: "number",
            description: "Probability that this image matches the system description (0-1)"),
          "visible_fraction": FunctionProperty(
            type: "number",
            description: "Approximate fraction (0-1) of the vehicle’s exterior visible in the image"
          ),
          "reason": FunctionProperty(
            type: "string",
            description:
              "If match is false, reason for non-match (enum value) else success. If the image is blurry or unclear or ambiguous prefer those to wrong_model_or_color.",
            enumValues: [
              "success",
              "unclear_image",
              "wrong_object_class",
              "wrong_model_or_color",
              "ambiguous",
              "license_plate_mismatch",
              "other_mismatch",
            ]),
          "description": FunctionProperty(
            type: "string",
            description: "Short natural-language description of the object e.g. colour make model"),
        ],
        required: [
          "make", "model", "colour", "extract_confidence", "match", "match_confidence",
          "description", "visible_fraction", "reason",
        ])))

  // MARK: - Public API
  public func verify(image: UIImage) -> AnyPublisher<VerificationOutcome, Error> {
    let startTime = Date()
    guard let base64 = image.jpegData(compressionQuality: 0.7)?.base64EncodedString() else {
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    lastVerifiedDate = Date()

    // Single-step: build combined request
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let chat = ChatCompletionRequest(
      model: "gpt-4.1-mini",
      messages: [
        Message(
          role: "system",
          content: [
            MessageContent(
              text:
                """
                # Extraction and Deliberation
                Step 1 (extract): Carefully extract `make`, `model`, and `colour` from the image. If you are less than 90% confident in any field, set it to the string "unknown". Do not decide on match yet.
                Step 2 (decide): Using only the extracted fields and the reference, decide if all three match with high confidence. If any field is "unknown" or match_confidence < 0.9, set match = false and reason = "ambiguous".
                All confidence numbers must be rounded to the nearest 0.05 (e.g., 0.65, 0.90).

                # Strictness rule
                Err on the side of `match = false`. Do not agree with the user's description unless you are certain all attributes match.

                # Your role
                You are a skeptical verifier, not a matcher.

                # Skepticism
                If you are not certain, you must return match = false. Do not try to please the user or guess.

                # Never use empty strings for any field. Use "unknown" if less than 90% confident.
                # Reason "success" may only be used when match = true AND no field is "unknown".

                ## Matching rules
                * Treat similar colours as equal (silver ≈ gray). IMPORTANT
                * Ignore licence-plate information.

                ## Color Mapping
                * Silver, Charcoal, Gray, Black = Silver
                * White, Cream, Beige = White
                * Red, Maroon, Burgundy = Red
                * Blue, Azure, Royal = Blue
                * Green, Emerald, Teal = Green
                * Yellow, Gold = Yellow
                * Orange, Tan = Orange
                * Purple, Magenta = Purple

                | Condition                              | match | reason               |
                |----------------------------------------|-------|----------------------|
                | Blurry / low-res / occluded / unclear  | false | unclear_image        |
                | Ambiguous viewpoint / missing cues     | false | ambiguous            |
                | Wrong make / model / colour            | false | wrong_model_or_color |
                | Clear match                            | true  | success              |

                ## Examples
                <example id="ambiguous_unknown">
                  <image_desc>Blurry side view of a white SUV</image_desc>
                  <reference_desc>white Toyota Highlander</reference_desc>
                  <assistant_tool_call>{
                    "make": "unknown",
                    "model": "unknown",
                    "colour": "white",
                    "extract_confidence": 0.65,
                    "visible_fraction": 0.7,
                    "match": false,
                    "match_confidence": 0.6,
                    "reason": "ambiguous",
                    "description": "white SUV, make/model unclear"
                  }</assistant_tool_call>
                </example>
                <example id="ambiguous_similar_vehicle">
                  <image_desc>Side view of a silver Nissan Rogue</image_desc>
                  <reference_desc>gray Hyundai Tucson</reference_desc>
                  <assistant_tool_call>{
                    "make": "unknown",
                    "model": "unknown",
                    "colour": "silver",
                    "extract_confidence": 0.82,
                    "visible_fraction": 0.85,
                    "match": false,
                    "match_confidence": 0.7,
                    "reason": "ambiguous",
                    "description": "silver SUV, badge/model unclear"
                  }</assistant_tool_call>
                </example>

                <example id="ambiguous_similar_colour">
                  <image_desc>Rear view of a dark gray Audi Q3</image_desc>
                  <reference_desc>black Volvo XC60</reference_desc>
                  <assistant_tool_call>{
                    "make": "Audi",
                    "model": "unknown",
                    "colour": "gray",
                    "extract_confidence": 0.85,
                    "visible_fraction": 0.9,
                    "match": false,
                    "match_confidence": 0.75,
                    "reason": "ambiguous",
                    "description": "dark gray Audi SUV, model unclear"
                  }</assistant_tool_call>
                </example>

                <example id="match">
                <image_desc>A red Toyota Corolla sedan</image_desc>
                <reference_desc>red Toyota Corolla</reference_desc>
                <assistant_tool_call>{
                  "make":"Toyota",
                  "model":"Corolla",
                  "colour":"red",
                  "extract_confidence":0.95,
                  "visible_fraction":1.0,
                  "match":true,
                  "match_confidence":0.93,
                  "reason":"success"
                }</assistant_tool_call>
                </example>

                <example id="wrong-colour">
                <image_desc>A blue Honda Civic hatchback</image_desc>
                <reference_desc>red Honda Civic</reference_desc>
                <assistant_tool_call>{
                  "make":"Honda",
                  "model":"Civic",
                  "colour":"blue",
                  "extract_confidence":0.90,
                  "visible_fraction":0.9,
                  "match":false,
                  "match_confidence":0.04,
                  "reason":"wrong_model_or_color"
                }</assistant_tool_call>
                </example>

                <example id="blurry">
                <image_desc>Blurry side-view of a silver sedan</image_desc>
                <reference_desc>silver BMW 3 Series</reference_desc>
                <assistant_tool_call>{
                  "make": "unknown",
                  "model": "unknown",
                  "colour": "unknown",
                  "extract_confidence": 0.20,
                  "visible_fraction": 0.3,
                  "match": false,
                  "match_confidence": 0.12,
                  "reason": "unclear_image",
                  "description": "Blurry image"
                }</assistant_tool_call>
                </example>
                <example id="partial-side">

                <image_desc>Rear-quarter view; only tail-lights visible</image_desc>
                <reference_desc>white Tesla Model 3</reference_desc>
                <assistant_tool_call>{
                  "make":"unknown",
                  "model":"unknown",
                  "colour":"unknown",
                  "extract_confidence":0.35,
                  "visible_fraction":0.25,
                  "match":false,
                  "match_confidence":0.10,
                  "reason":"unclear_image"
                }</assistant_tool_call>
                </example>

                <example id="similar-ambiguous">
                <image_desc>Front view of a dark BMW sedan; only grille and headlights visible</image_desc>
                <reference_desc>black BMW 5 Series</reference_desc>
                <assistant_tool_call>{
                  "make":"BMW",
                  "model":"unknown",
                  "colour":"black",
                  "extract_confidence":0.70,
                  "visible_fraction":0.4,
                  "match":false,
                  "match_confidence":0.30,
                  "reason":"ambiguous"
                }</assistant_tool_call>
                </example>

                -- END DEVELOPER MESSAGE --
                """
            )
          ]),
        Message(
          role: "user",
          content: [
            MessageContent(text: "We are checking if the image contains a \(targetTextDescription)")
          ]
        ),
        Message(
          role: "user",
          content: [MessageContent(imageURL: "data:image/png;base64,\(base64)")]
        ),
      ],
      tools: [Self.combinedToolSchema],
      max_tokens: 120)
    req.httpBody = try? encoder.encode(chat)

    return URLSession.shared.dataTaskPublisher(for: req)
      .tryMap { $0.data }
      // .handleEvents(receiveOutput: { data in
      //   if let jsonString = String(data: data, encoding: .utf8) {
      //     print(jsonString)
      //   }
      // })
      .decode(type: ChatCompletionResponse.self, decoder: decoder)
      .tryMap { resp in
        guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          throw NSError(
            domain: "AdvancedLLMVerifier", code: 0,
            userInfo: [NSLocalizedDescriptionKey: "No tool args"])
        }
        let combined = try self.decoder.decode(CombinedVehicleMatch.self, from: data)
        print(combined)
        // Handle confidence, ambiguity, etc. as before
        // Early reject for insufficient visible area
        if combined.visible_fraction < 0.8 {
          return VerificationOutcome(
            isMatch: false,
            description: combined.description ?? "",
            rejectReason: .ambiguous
          )
        }
        if !combined.match {
          return VerificationOutcome(
            isMatch: false,
            description: "\(combined.make) \(combined.model)",
            rejectReason: RejectReason(rawValue: combined.reason ?? "api_error")
          )
        }
        if combined.match_confidence < self.confidenceThreshold {
          return VerificationOutcome(
            isMatch: false,
            description: combined.description ?? "",
            rejectReason: .lowConfidence
          )
        }
        return VerificationOutcome(
          isMatch: combined.match,
          description: combined.description ?? "",
          rejectReason: combined.reason == nil ? nil : RejectReason(rawValue: combined.reason!)
        )
      }
      .handleEvents(
        receiveOutput: { _ in
          let latency = Date().timeIntervalSince(startTime)
          print("[AdvancedLLMVerifier] latency: \(latency)s")
        },
        receiveCompletion: { _ in
        }
      )
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    Date().timeIntervalSince(lastVerifiedDate)
  }

  // MARK: - Helpers & models
  // Combined struct for decoding the LLM response
  private struct CombinedVehicleMatch: Codable {
    let make: String
    let model: String
    let colour: String?
    let extract_confidence: Double
    let match: Bool
    let match_confidence: Double
    let visible_fraction: Double
    let reason: String?
    let description: String?
  }
}
