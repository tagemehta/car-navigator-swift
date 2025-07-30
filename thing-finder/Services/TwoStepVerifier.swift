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

  // Similarity threshold (Jaccard) to decide if step-2 confirmation is needed
  private let similarityThreshold: Double = 0.6
  private let confidenceThreshold: Double = 0.86

  public init(targetTextDescription: String) { self.targetTextDescription = targetTextDescription }

  // MARK: - Tool schemas (reuse struct types from LLMVerifier)
  private static let extractToolSchema: Tool = Tool(
    function: Function(
      name: "extract_vehicle_info",
      description: "Extract make, model, colour, body_style from the image.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "make": FunctionProperty(type: "string", description: "Vehicle manufacturer"),
          "model": FunctionProperty(type: "string", description: "Specific model"),
          "colour": FunctionProperty(type: "string", description: "Dominant colour"),
          "confidence": FunctionProperty(type: "number", description: "Confidence 0-1"),
        ],
        required: ["make", "model", "colour", "confidence"])))

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
            description: "Short natural-language description of the object e.g. colour make model"),
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
      model: "gpt-4o",
      messages: [
        Message(
          role: "system",
          content: [MessageContent(text: "Identify the vehicle. Respond ONLY via tool call.")]),
        Message(
          role: "user", content: [MessageContent(imageURL: "data:image/png;base64,\(base64)")]),
      ],
      tools: [Self.extractToolSchema],
      max_tokens: 50)
    req1.httpBody = try? encoder.encode(chat1)

    return URLSession.shared.dataTaskPublisher(for: req1)
      .handleEvents(receiveOutput: { output in
      })
      .tryMap { return $0.data }
      .decode(type: ChatCompletionResponse.self, decoder: decoder)
      .tryMap { resp -> (VehicleInfo, Double) in
        guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          throw NSError(
            domain: "TwoStep", code: 0, userInfo: [NSLocalizedDescriptionKey: "No tool args"])
        }
        let info = try self.decoder.decode(VehicleInfo.self, from: data)
        let sim = Self.jaccard(
          tokensFrom: "\(info.make) \(info.model)", tokensFrom: self.targetTextDescription)
        return (info, sim)
      }
      .flatMap { [weak self] (info, sim) -> AnyPublisher<VerificationOutcome, Error> in
        guard let self else {
          return Fail(error: URLError(.badServerResponse)).eraseToAnyPublisher()
        }
        // If similarity low → ambiguous early exit
        guard sim >= self.similarityThreshold else {
          return Just(
            VerificationOutcome(
              isMatch: false, description: "\(info.make) \(info.model)", rejectReason: "ambiguous")
          )
          .setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        // 2️⃣ Build confirmation request
        var req2 = URLRequest(url: self.endpoint)
        req2.httpMethod = "POST"
        req2.setValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
        req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let chat2 = ChatCompletionRequest(
          model: "gpt-4o",
          messages: [
            Message(
              role: "system",
              content: [MessageContent(text: "You are a strict verifier. Respond via tool only.")]),
            Message(
              role: "user",
              content: [
                MessageContent(text: "Does this image match: \(self.targetTextDescription) ?"),
                MessageContent(imageURL: "data:image/png;base64,\(base64)"),
              ]),
          ],
          tools: [Self.matchToolSchema],
          max_tokens: 100)
        req2.httpBody = try? self.encoder.encode(chat2)

        return URLSession.shared.dataTaskPublisher(for: req2)
          .handleEvents(receiveOutput: { output in
          })
          .tryMap { pair -> Data in
            let data = pair.data
            return data
          }
          .decode(type: ChatCompletionResponse.self, decoder: self.decoder)
          .tryMap { resp in
            print("1")
            guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
              let data = argStr.data(using: .utf8)
            else {
              return VerificationOutcome(
                isMatch: false, description: "\(info.make) \(info.model)", rejectReason: "ambiguous"
              )
            }
            print("2")
            let m = try self.decoder.decode(MatchResult.self, from: data)
            if m.match && m.confidence < self.confidenceThreshold {
              return VerificationOutcome(
                isMatch: false, description: m.description!, rejectReason: "low_confidence")
            }
            return VerificationOutcome(
              isMatch: m.match, description: m.description!, rejectReason: m.match ? nil : m.reason)
          }
          .eraseToAnyPublisher()
      }
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    Date().timeIntervalSince(lastVerifiedDate)
  }

  // MARK: - Helpers & models
  private struct VehicleInfo: Codable {
    let make: String
    let model: String
    let colour: String?
    let confidence: Double
  }

  private static func tokensFrom(_ s: String) -> Set<String> {
    Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
  }
  private static func jaccard(tokensFrom a: String, tokensFrom b: String) -> Double {
    let A = tokensFrom(a)
    let B = tokensFrom(b)
    let inter = A.intersection(B).count
    let union = A.union(B).count
    return union == 0 ? 0 : Double(inter) / Double(union)
  }
}
