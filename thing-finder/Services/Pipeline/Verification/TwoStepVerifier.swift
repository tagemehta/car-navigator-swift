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

enum TwoStepError: Error {
  case noToolResponse
  case occluded
  case lowConfidence
  case networkError
}

public final class TwoStepVerifier: ImageVerifier {
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

  private let confidenceThreshold: Double = 0.90

  public init(targetTextDescription: String) { self.targetTextDescription = targetTextDescription }

  // MARK: - Tool schemas (reuse struct types from LLMVerifier)
  // Step 1 – identification
  private static let extractToolSchema: Tool = Tool(
    function: Function(
      name: "extract_vehicle_info",
      description: "Extract make, model, color, body_style from the image.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "make": FunctionProperty(type: "string", description: "Vehicle manufacturer"),
          "make_score": FunctionProperty(
            type: "number", description: "Confidence in your prediction of make 0-1"),
          "model_score": FunctionProperty(
            type: "number", description: "Confidence in your prediction of model 0-1"),
          "color_score": FunctionProperty(
            type: "number", description: "Confidence in your prediction of color 0-1"),
          "model": FunctionProperty(type: "string", description: "Specific model"),
          "view": FunctionProperty(
            type: "string",
            description: "Orientation of the vehicle e.g. front, rear, side, unknown",
            enumValues: ["front", "rear", "side", "unknown"]),
          "color": FunctionProperty(type: "string", description: "Dominant color"),
          "confidence": FunctionProperty(
            type: "number", description: "Confidence 0-1 (two decimals, 0.01 steps)"),
          "visible_fraction": FunctionProperty(
            type: "number",
            description: "Approximate fraction (0-1) of the vehicle visible in the image"),
        ],
        required: [
          "make", "model", "color", "view", "make_score", "model_score", "color_score",
          "confidence", "visible_fraction",
        ])))

  // Reuse match_tool from LLMVerifier via static helper for consistency
  private static let matchToolSchema: Tool = Tool(
    function: Function(
      name: "match_object",
      description: "Determines if the image matches the given description.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "match": FunctionProperty(
            type: "boolean", description: "Indicates if the image matches the description."),
          "confidence": FunctionProperty(
            type: "number", description: "Probability that this is a match (0-1)"),
          "reason": FunctionProperty(
            type: "string",
            description: "If match=false, why not? Enum value.",
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
            description: "Short natural-language description of the object e.g. color make model"),
        ],
        required: ["match", "confidence", "description", "reason"])))

  // MARK: - Public API
  public func verify(image: UIImage) -> AnyPublisher<VerificationOutcome, Error> {
    guard let base64 = image.jpegData(compressionQuality: 1)?.base64EncodedString() else {
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    lastVerifiedDate = Date()

    // 1️⃣ Build step-1 request (extract)
    var req1 = URLRequest(url: endpoint)
    req1.httpMethod = "POST"
    req1.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req1.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let chat1 = ChatCompletionRequest(
      model: "gpt-4.1-mini",
      messages: [
        Message(
          role: "system",
          content: [MessageContent(text: "Identify the vehicle. Respond ONLY via tool call.")]),
        Message(
          role: "user", content: [MessageContent(imageURL: "data:image/png;base64,\(base64)")]),
      ],
      tools: [Self.extractToolSchema],
      max_tokens: 100)
    req1.httpBody = try? encoder.encode(chat1)

    return URLSession.shared.dataTaskPublisher(for: req1)
      .handleEvents(receiveOutput: { output in
      })
      .tryMap { return $0.data }
      .decode(type: ChatCompletionResponse.self, decoder: decoder)
      .tryMap { resp -> VehicleInfo in
        guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          // Return a specific outcome instead of throwing
          throw TwoStepError.noToolResponse
        }
        let info = try self.decoder.decode(VehicleInfo.self, from: data)
        print(info)
        // Early reject for heavy occlusion
        if info.visible_fraction < 0.5 {
          throw TwoStepError.occluded
        }
        // Reject low extraction confidence to curb over-confidence
        if info.confidence < 0.9 {
          throw TwoStepError.lowConfidence
        }
        return info
      }
      .flatMap { [weak self] info -> AnyPublisher<VerificationOutcome, Error> in
        guard let self else {
          return Fail(error: URLError(.badServerResponse)).eraseToAnyPublisher()
        }
        // 2️⃣ Build comparison request via LLM (shared logic from TrafficEye)
        return self.callLLMForComparison(with: info)
      }
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    Date().timeIntervalSince(lastVerifiedDate)
  }

  // MARK: - LLM Comparison (step 2)
  private func callLLMForComparison(with vehicleInfo: VehicleInfo) -> AnyPublisher<
    VerificationOutcome, Error
  > {
    // Serialize VehicleInfo to JSON for the prompt
    let infoJSON: String = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      if let data = try? encoder.encode(vehicleInfo), let str = String(data: data, encoding: .utf8)
      {
        return str
      }
      return "{}"
    }()

    let systemPrompt = """
      You are a vehicle verification expert. You are given the output of an ML vehicle recognition API (including make, model, color, and confidence scores for each), and a user's natural language description of their vehicle. The ML output may be imperfect.
      Your job is to estimate the probability (0-1) that the ML prediction refers to the same car as described by the user, **and** provide a semantic_reason:
      - \"match\" if confident they are the same car.
      - \"mismatch\" if confident they are different.
      - \"maybe\" when uncertain or info is missing.
      You are necessary because there are differences in the technical api output and the plain language user input (like dashes, abbreviations, slight color differences) and we still need a robust way to match the descriptions.
      Consider:
      - If the make and color are correct and the model is similar (and low-confidence), a match is likely.
      - If the api provides more information than the user, (e.g. API - Red honda civic User - Honda civic or Red civic) consider them to be equal
      - If the make is correct but the model is very different (e.g. Accord vs CR-V), it's likely not a match.
      - If a license plate is part of the user prompt but none is provided by the api, treat it as a non-factor
      The API only outputs colors as \"BLUE\", \"BROWN\", \"YELLOW\", \"GRAY\", \"GREEN\", \"PURPLE\", \"RED\", \"WHITE\", \"BLACK\", \"ORANGE\".
      Therefore, treat colors that are roughly equivalent (silver vs gray) as equal
      - Take the confidence scores into account for each attribute.
      Output your reasoning and call the submit_match_decision function with your probability and justification.
      """

    let userPrompt = """
      ML API prediction (JSON):
      \(infoJSON)
      User's description: '\(targetTextDescription)'
      What is the probability (0-1) that the ML prediction is referring to the same car as the user described? Justify briefly.
      """

    let requestPayload = ChatCompletionRequest(
      model: "gpt-4.1-mini",
      messages: [
        Message(role: "system", content: [MessageContent(text: systemPrompt)]),
        Message(role: "user", content: [MessageContent(text: userPrompt)]),
      ],
      tools: [
        Tool(
          function: Function(
            name: "submit_match_decision",
            description: "Submit the verification probability and justification.",
            parameters: FunctionParameters(
              type: "object",
              properties: [
                "probability_match": .init(
                  type: "number",
                  description:
                    "Estimated probability (0-1) that the ML prediction refers to the same car as described by the user."
                ),
                "semantic_reason": .init(
                  type: "string",
                  description:
                    "Match if confident they are the same car. Mismatch if confident they are different. Maybe when uncertain or info is missing.",
                  enumValues: ["match", "maybe", "mismatch"]),
              ], required: ["probability_match", "semantic_reason"]))
        )
      ],
      max_tokens: 50)

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.httpBody = try? JSONEncoder().encode(requestPayload)

    return URLSession.shared.dataTaskPublisher(for: req)
      .tryMap { $0.data }
      .decode(type: ChatCompletionResponse.self, decoder: decoder)
      .tryMap { resp -> VerificationOutcome in
        guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          throw URLError(.badServerResponse)
        }
        struct LLMResult: Decodable {
          let probability_match: Double
          let semantic_reason: String
        }
        let args = try self.decoder.decode(LLMResult.self, from: data)
        let infoQ =
          0.5 * vehicleInfo.make_score + 0.3 * vehicleInfo.model_score + 0.2
          * vehicleInfo.color_score
        let qualityLevel = infoQ >= 0.85 ? "high" : (infoQ >= 0.4 ? "medium" : "low")
        var isMatch = false
        var reject: RejectReason = .insufficientInfo
        if qualityLevel == "high" {
          switch args.semantic_reason {
          case "match":
            isMatch = true
            reject = .success
          case "maybe":
            isMatch = false
            reject = .lowConfidence
          default:
            isMatch = false
            reject = .wrongModelOrColor
          }
        } else {
          switch args.semantic_reason {
          case "match":
            isMatch = true
            reject = .success
          default:
            isMatch = false
            reject = .insufficientInfo
          }
        }
        return VerificationOutcome(
          isMatch: isMatch,
          description: "\(vehicleInfo.color ?? "") \(vehicleInfo.make) \(vehicleInfo.model)",
          rejectReason: reject,
          vehicleView: Self.mapView(vehicleInfo.view),
          viewScore: vehicleInfo.visible_fraction)
      }
      .eraseToAnyPublisher()
  }

  // MARK: - Helpers & models
  private static func mapView(_ str: String) -> Candidate.VehicleView {
    switch str.lowercased() {
    case "front", "frontal": return .front
    case "rear", "back": return .rear
    case "side", "lateral": return .side
    default: return .unknown
    }
  }

  // MARK: - Helper DTOs
  private struct VehicleInfo: Codable {
    let make: String
    let model: String
    let view: String
    let color: String?
    var make_score: Double
    var model_score: Double
    var color_score: Double
    var confidence: Double
    let visible_fraction: Double
  }
}
