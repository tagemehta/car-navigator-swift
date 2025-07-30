import Combine
import Foundation
import UIKit

// MARK: - TrafficEye API Data Models

private struct TrafficEyeRecognitionRequest: Codable {
  let saveImage: Bool
  let tasks: [String]

  init() {
    self.saveImage = false
    // Include OCR so we get license plate text in response
    self.tasks = ["DETECTION", "OCR", "MMR"]
  }
}

// Corrected models based on API response example
private struct TrafficEyeResponse: Codable {
  let data: TrafficEyeData?
}

private struct TrafficEyeData: Codable {
  let combinations: [Combination]?
}

private struct Combination: Codable {
  let roadUsers: [RoadUser]?
}

private struct PlateText: Codable {
  let value: String
  let score: Double?
}
private struct Plate: Codable {
  let text: PlateText
}

private struct RoadUser: Codable {
  let mmr: MMR?
  let plates: [Plate]?
}

private struct MMR: Codable {
  let make: MMRItem?
  let model: MMRItem?
  let color: MMRItem?
}

private struct MMRItem: Codable {
  let value: String
  let score: Double
}

// MARK: - TrafficEye Verifier

public final class TrafficEyeVerifier: ImageVerifier {
  private var lastVerifiedDate = Date()

  private let trafficEyeEndpoint = URL(string: "https://trafficeye.ai/recognition")!
  private let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

  private let trafficEyeApiKey = Bundle.main.infoDictionary!["TRAFFICEYE_API_KEY"] as! String
  private let openAIApiKey = Bundle.main.infoDictionary!["OPENAI_API"] as! String

  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let confidenceThresholdMatch: Double = 0.80
  private let confidenceThresholdAmbiguous: Double = 0.60

  private let imgUtils = ImageUtilities.shared

  public let targetClasses: [String]
  public let targetTextDescription: String
  public let config: VerificationConfig

  init(targetClasses: [String] = ["car"], targetTextDescription: String, config: VerificationConfig)
  {
    self.targetClasses = targetClasses
    self.targetTextDescription = targetTextDescription
    self.config = config
  }

  public func verify(image: UIImage) -> AnyPublisher<VerificationOutcome, Error> {
    lastVerifiedDate = Date()
    let blurScore = imgUtils.blurScore(from: image)
    guard blurScore != nil && imgUtils.blurScore(from: image)! < 0.1 else {
      return Just(
        VerificationOutcome(isMatch: false, description: "blurry", rejectReason: "unclear_image")
      ).setFailureType(to: Error.self)  // promote to Error failure
        .eraseToAnyPublisher()
    }
    guard let imageBytes = image.jpegData(compressionQuality: 1) else {
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    return callTrafficEyeAPI(imageBytes: imageBytes)
      .catch { _ in Just(RecognitionResult(mmr: nil, plate: nil)).setFailureType(to: Error.self) }
      .flatMap { result -> AnyPublisher<VerificationOutcome, Error> in
        // --- License plate early verification ---
        /*if let expectedPlate = self.config.expectedPlate,
          let detectedPlate = result.plate
        {
          let expectedNorm = expectedPlate.replacingOccurrences(of: " ", with: "").uppercased()
          let detectedNorm = detectedPlate.text.value.replacingOccurrences(of: " ", with: "").uppercased()

          if detectedNorm == expectedNorm {
            // Perfect match – success
            let outcome = VerificationOutcome(
              isMatch: true, description: detectedPlate.text.value, rejectReason: "success")
            return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
          } else if (detectedPlate.text.score ?? 0) >= self.config.ocrConfidenceMin
            && detectedNorm.count == expectedNorm.count
          {
            // High-conf mismatch – reject early
            let mmcDesc = [
              result.mmr?.color?.value, result.mmr?.make?.value, result.mmr?.model?.value,
            ]
            .compactMap { $0 }.joined(separator: " ")
            let outcome = VerificationOutcome(
              isMatch: false,
              description: "\(mmcDesc) \(detectedPlate.text.value)",
              rejectReason: "license_plate_mismatch")
            return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
          }
          // Low confidence or length mismatch – proceed to LLM
        } */

        guard let mmr = result.mmr else {
          // No vehicle detection at all
          let outcome = VerificationOutcome(
            isMatch: false, description: "No vehicle detected", rejectReason: "api_error")
          return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        // Defer to LLM for make/model/color comparison
        return self.callLLMForComparison(with: mmr)
      }
      .eraseToAnyPublisher()
  }

  private struct RecognitionResult {
    let mmr: MMR?
    let plate: Plate?
  }

  private func callTrafficEyeAPI(imageBytes: Data) -> AnyPublisher<RecognitionResult, Error> {
    // print("[DEBUG] Sending TrafficEye API request...")
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: trafficEyeEndpoint)
    request.httpMethod = "POST"
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(trafficEyeApiKey, forHTTPHeaderField: "apiKey")

    let requestBody = createMultipartBody(boundary: boundary, image: imageBytes)
    request.httpBody = requestBody

    return URLSession.shared.dataTaskPublisher(for: request)
      .tryMap { $0.data }
      .decode(type: TrafficEyeResponse.self, decoder: jsonDecoder)
      .map { response -> RecognitionResult in
        let combinations = response.data?.combinations ?? []
        guard let first = combinations.first,
          let roadUser = first.roadUsers?.first,
          !combinations.isEmpty
        else {
          // No detections or missing data
          return RecognitionResult(mmr: nil, plate: nil)
        }
        return RecognitionResult(mmr: roadUser.mmr, plate: roadUser.plates?.max(by: { p1, p2 in
          p1.text.score ?? 0 < p2.text.score ?? 0
          // A predicate that returns true if its first argument should be ordered before its second argument [for increasing order]; otherwise, false.
        }))
      }
      // .handleEvents(receiveCompletion: { completion in
      //   if case .failure(let err) = completion {
      //     print("[DEBUG] TrafficEye API error: \(err)")
      //   }
      // })
      .eraseToAnyPublisher()
  }

  private func createMultipartBody(boundary: String, image: Data) -> Data {
    var body = Data()
    let lineBreak = "\r\n"

    // Add JSON part for the request
    let apiRequest = TrafficEyeRecognitionRequest()
    let jsonData = try! jsonEncoder.encode(apiRequest)
    body.append("--\(boundary + lineBreak)".data(using: .utf8)!)
    body.append(
      "Content-Disposition: form-data; name=\"request\"\(lineBreak + lineBreak)".data(using: .utf8)!
    )
    body.append(jsonData)
    body.append(lineBreak.data(using: .utf8)!)

    // Add image data part
    body.append("--\(boundary + lineBreak)".data(using: .utf8)!)
    body.append(
      "Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\(lineBreak)".data(
        using: .utf8)!)
    body.append("Content-Type: image/jpeg\(lineBreak + lineBreak)".data(using: .utf8)!)
    body.append(image)
    body.append(lineBreak.data(using: .utf8)!)

    body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
    return body
  }

  private func callLLMForComparison(with mmrResult: MMR) -> AnyPublisher<
    VerificationOutcome, Error
  > {
    // Serialize the full MMR object (including confidences) as JSON for LLM prompt
    let mmrJSON: String = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      if let data = try? encoder.encode(mmrResult), let str = String(data: data, encoding: .utf8) {
        return str
      }
      return "{\"make\":null,\"model\":null,\"color\":null}"
    }()

    let systemPrompt = """
      You are a vehicle verification expert. You are given the output of an ML vehicle recognition API (including make, model, color, and confidence scores for each), and a user's natural language description of their vehicle. The ML output may be imperfect.
      Your job is to estimate the probability (0-1) that the ML prediction refers to the same car as described by the user.
      You are necessary because there are differences in the technical api output and the plain language user input (like dashes, abbreviations, slight color differences)  and we still need a robust way to match the descriptions.
      Consider:
      - If the make and color are correct and the model is similar (and low-confidence), a match is likely.
      - If the api provides more information than the user, (e.g. API - Red honda civic User - Honda civic or Red civic) consider them to be equal
      - If the make is correct but the model is very different (e.g. Accord vs CR-V), it's likely not a match.
      - 
      - If a license plate is part of the user prompt but none is provided by the api, treat it as a non-factor
      The API only outputs colors as "BLUE", "BROWN", "YELLOW", "GRAY", "GREEN", "PURPLE", "RED", "WHITE", "BLACK", "ORANGE".
      Therefore, treat colors that are roughly equivalent (silver vs gray, as equal)
      - Take the confidence scores into account for each attribute.
      Output your reasoning and call the submit_match_decision function with your probability and justification.
      """

    let userPrompt = """
      ML API prediction (JSON):
      \(mmrJSON)
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
          function:
            Function(
              name: "submit_match_decision",
              description: "Submit the verification probability and justification.",
              parameters: FunctionParameters(
                type: "object",
                properties: [
                  "probability_match": .init(
                    type: "number",
                    description:
                      "Estimated probability (0-1) that the ML prediction refers to the same car as described by the user. Treat similar colors (silver and gray as equal)"
                  ),
                  "reason": .init(
                    type: "string", description: "10 words or less justify your prediction"),
                ], required: ["probability_match", "reason"]))
        )
      ], max_tokens: 50
    )
    var request = URLRequest(url: openAIEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(requestPayload)
    let _ = Date()
    return URLSession.shared.dataTaskPublisher(for: request)
      .tryMap { $0.data }
      .decode(type: ChatCompletionResponse.self, decoder: jsonDecoder)
      .tryMap { response -> VerificationOutcome in
        guard let argStr = response.choices.first?.message.tool_calls?.first?.function.arguments,
          let data = argStr.data(using: .utf8)
        else {
          throw URLError(
            .badServerResponse,
            userInfo: [NSLocalizedDescriptionKey: "Malformed OpenAI tool call response"])
        }
        struct LLMProbabilityResult: Decodable {
          let probability_match: Double
          let reason: String
        }
        let args = try self.jsonDecoder.decode(LLMProbabilityResult.self, from: data)
        let isMatch = args.probability_match > self.confidenceThresholdMatch
        let rejectReason =
          isMatch
          ? "success"
          : args.probability_match > self.confidenceThresholdAmbiguous
            ? "low_confidence" : "wrong_model_or_color"
        return VerificationOutcome(
          isMatch: isMatch,
          description:
            "\(mmrResult.color?.value ?? "") \(mmrResult.make?.value ?? "") \(mmrResult.model?.value ?? "")",
          rejectReason: rejectReason
        )
      }
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    return Date().timeIntervalSince(lastVerifiedDate)
  }
}
