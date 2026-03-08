//  AdvancedLLMVerifier.swift
//
//  Simplified LLM verifier for transit/bus verification.
//  Uses a minimal 3-field tool call: verdict, confidence, reason.
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

  private let confidenceThreshold: Double = 0.80

  public init(targetTextDescription: String) {
    self.targetTextDescription = targetTextDescription
  }

  // MARK: - Simplified Tool Schema
  private static let verifyToolSchema: Tool = Tool(
    function: Function(
      name: "verify_match",
      description: "Determine if the image matches the target description.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "verdict": FunctionProperty(
            type: "string",
            description:
              "Your decision: match (clearly the target), unclear (can't tell yet), or reject (clearly not the target)",
            enumValues: ["match", "unclear", "reject"]
          ),
          "confidence": FunctionProperty(
            type: "number",
            description: "How confident are you in this verdict? 0.0 to 1.0"
          ),
          "reason": FunctionProperty(
            type: "string",
            description:
              "Brief explanation (e.g. 'Route 42 visible on front', 'bus angled away', 'shows Route 15 not 42')"
          ),
        ],
        required: ["verdict", "confidence", "reason"]
      )
    )
  )

  // MARK: - System Prompt
  private var systemPrompt: String {
    """
    You are verifying if an image shows a specific vehicle the user is looking for.

    The user will describe what they're looking for (e.g. "Route 42 bus", "blue MTA bus", "SEPTA bus").

    Look at the image and decide:
    - **match**: You can clearly see this IS the target (route number matches, agency logo visible, etc.)
    - **unclear**: You can't tell yet (bus is angled, number not visible, too blurry, partially obscured)
    - **reject**: You can clearly see this is NOT the target (different route number, different agency, not even a bus)

    Be conservative:
    - If you can't read the route number clearly, say "unclear" not "match"
    - Only say "reject" if you're certain it's wrong (e.g. you can clearly read "Route 15" when looking for "Route 42")
    - Only say "match" if you can clearly confirm the identifying features
    """
  }

  // MARK: - Public API
  public func verify(image: UIImage, candidateId: UUID) -> AnyPublisher<VerificationOutcome, Error>
  {
    let startTime = Date()
    DebugPublisher.shared.info(
      "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Starting verification...")

    guard let base64 = image.jpegData(compressionQuality: 0.7)?.base64EncodedString() else {
      DebugPublisher.shared.error(
        "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Failed to encode image")
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    lastVerifiedDate = Date()

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let chat = ChatCompletionRequest(
      model: "gpt-4.1-mini",
      messages: [
        Message(role: "system", content: [MessageContent(text: systemPrompt)]),
        Message(
          role: "user",
          content: [
            MessageContent(text: "Looking for: \(targetTextDescription)")
          ]
        ),
        Message(
          role: "user",
          content: [MessageContent(imageURL: "data:image/jpeg;base64,\(base64)")]
        ),
      ],
      tools: [Self.verifyToolSchema],
      max_tokens: 100
    )
    req.httpBody = try? encoder.encode(chat)

    return URLSession.shared.dataTaskPublisher(for: req)
      .handleEvents(receiveOutput: { output in
        DebugPublisher.shared.info(
          "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Received response (\(output.data.count) bytes)"
        )
      })
      .tryMap { $0.data }
      .decode(type: ChatCompletionResponse.self, decoder: decoder)
      .tryMap { [weak self] resp -> VerificationOutcome in
        guard let self = self else {
          throw NSError(domain: "AdvancedLLMVerifier", code: 0, userInfo: nil)
        }
        guard let argStr = resp.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          DebugPublisher.shared.error(
            "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] No tool call in response")
          throw NSError(
            domain: "AdvancedLLMVerifier", code: 0,
            userInfo: [NSLocalizedDescriptionKey: "No tool args"])
        }

        let result = try self.decoder.decode(VerifyResult.self, from: data)
        DebugPublisher.shared.info(
          "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Result: verdict=\(result.verdict ?? "nil") confidence=\(String(format: "%.2f", result.confidence ?? 0)) reason=\(result.reason ?? "nil")"
        )

        return self.mapToOutcome(result: result, candidateId: candidateId)
      }
      .handleEvents(
        receiveOutput: { outcome in
          let latency = Date().timeIntervalSince(startTime)
          if outcome.isMatch {
            DebugPublisher.shared.success(
              "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] MATCH (latency: \(String(format: "%.2f", latency))s)"
            )
          } else {
            DebugPublisher.shared.warning(
              "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] \(outcome.rejectReason?.rawValue ?? "rejected") (latency: \(String(format: "%.2f", latency))s)"
            )
          }
        },
        receiveCompletion: { completion in
          if case .failure(let err) = completion {
            DebugPublisher.shared.error(
              "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Failed: \(err.localizedDescription)"
            )
          }
        }
      )
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    Date().timeIntervalSince(lastVerifiedDate)
  }

  // MARK: - Response Mapping
  private func mapToOutcome(result: VerifyResult, candidateId: UUID) -> VerificationOutcome {
    let verdict = result.verdict ?? "unclear"
    let confidence = result.confidence ?? 0

    switch verdict {
    case "match":
      if confidence >= confidenceThreshold {
        return VerificationOutcome(
          isMatch: true,
          description: targetTextDescription,
          rejectReason: .success
        )
      } else {
        DebugPublisher.shared.warning(
          "[AdvancedLLM][\(candidateId.uuidString.suffix(8))] Match verdict but low confidence (\(String(format: "%.2f", confidence)))"
        )
        return VerificationOutcome(
          isMatch: false,
          description: result.reason ?? "",
          rejectReason: .lowConfidence
        )
      }

    case "reject":
      return VerificationOutcome(
        isMatch: false,
        description: result.reason ?? "",
        rejectReason: .wrongModelOrColor
      )

    case "unclear":
      return VerificationOutcome(
        isMatch: false,
        description: result.reason ?? "",
        rejectReason: .ambiguous
      )

    default:
      return VerificationOutcome(
        isMatch: false,
        description: result.reason ?? "",
        rejectReason: .ambiguous
      )
    }
  }

  // MARK: - Response Model
  private struct VerifyResult: Codable {
    let verdict: String?
    let confidence: Double?
    let reason: String?
  }
}
