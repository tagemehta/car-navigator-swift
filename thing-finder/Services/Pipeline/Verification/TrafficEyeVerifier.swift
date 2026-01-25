import Combine
import SwiftUI

// MARK: - TrafficEye API Data Models

private struct TrafficEyeRecognitionRequest: Codable {
  let saveImage: Bool
  let tasks: [String]
  // let mmrModuleNames: [String: String]

  init() {
    self.saveImage = false
    // Include OCR so we get license plate text in response
    self.tasks = ["DETECTION", "OCR", "MMR"]
    // self.mmrModuleNames = [
    //   "box": "CNN_MMRTF2LITE_VCMMGVCT_BGR_224x224_NONE_LIN_EXP25_PROTECTED_HASP_enc.dat"
    // ]
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
  let view: MMRItem?
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

  private let trafficEyeApiKey: String
  private let openAIApiKey: String

  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let confidenceThresholdMatch: Double = 0.80
  private let confidenceThresholdAmbiguous: Double = 0.60

  private let imgUtils: ImageUtilities
  private let urlSession: URLSessionProtocol

  public let targetClasses: [String]
  public let targetTextDescription: String
  public let config: VerificationConfig

  init(
    targetClasses: [String] = ["car"],
    targetTextDescription: String,
    config: VerificationConfig,
    imgUtils: ImageUtilities = .shared,
    urlSession: URLSessionProtocol = URLSession.shared,
    trafficEyeApiKey: String? = nil,
    openAIApiKey: String? = nil
  ) {
    self.targetClasses = targetClasses
    self.targetTextDescription = targetTextDescription
    self.config = config
    self.imgUtils = imgUtils
    self.urlSession = urlSession
    self.trafficEyeApiKey =
      trafficEyeApiKey ?? (Bundle.main.infoDictionary?["TRAFFICEYE_API_KEY"] as? String ?? "")
    self.openAIApiKey = openAIApiKey ?? (Bundle.main.infoDictionary?["OPENAI_API"] as? String ?? "")
  }

  public func verify(image: UIImage, candidateId: UUID) -> AnyPublisher<VerificationOutcome, Error>
  {
    let startTime = Date()
    lastVerifiedDate = startTime
    DebugPublisher.shared.info(
      "[TrafficEye][\(candidateId.uuidString.suffix(8))] ENTRY: verify() method called")
    DebugPublisher.shared.info(
      "[TrafficEye][\(candidateId.uuidString.suffix(8))] Starting verification...")
    let blurScore = imgUtils.blurScore(from: image)
    guard blurScore != nil && imgUtils.blurScore(from: image)! < 0.1 else {
      DebugPublisher.shared.warning(
        "[TrafficEye][\(candidateId.uuidString.suffix(8))] Rejecting: Image too blurry (blurScore=\(blurScore ?? -1))"
      )
      return Just(
        VerificationOutcome(isMatch: false, description: "blurry", rejectReason: .unclearImage)
      ).setFailureType(to: Error.self)  // promote to Error failure
        .eraseToAnyPublisher()
    }
    guard let imageBytes = image.jpegData(compressionQuality: 1) else {
      DebugPublisher.shared.error(
        "[TrafficEye][\(candidateId.uuidString.suffix(8))] Failed to convert image to JPEG data")
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    return callTrafficEyeAPI(imageBytes: imageBytes, candidateId: candidateId)
      .catch { error in
        DebugPublisher.shared.error(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] API call failed: \(error.localizedDescription)"
        )
        return Just(RecognitionResult(mmr: nil, plate: nil)).setFailureType(to: Error.self)
      }
      .flatMap { result -> AnyPublisher<VerificationOutcome, Error> in
        // --- License plate early verification ---
        if let expectedPlate = self.config.expectedPlate,
          let detectedPlate = result.plate
        {
          let expectedNorm = expectedPlate.replacingOccurrences(of: " ", with: "").uppercased()
          let detectedNorm = detectedPlate.text.value.replacingOccurrences(of: " ", with: "")
            .uppercased()

          if detectedNorm == expectedNorm {
            // Perfect match – success
            let vehicleView: Candidate.VehicleView = {
              switch result.mmr?.view?.value.lowercased() {
              case "frontal": return .front
              case "rear", "back": return .rear
              case "side": return .side
              default: return .unknown
              }
            }()
            let outcome = VerificationOutcome(
              isMatch: true,
              description: detectedPlate.text.value,
              rejectReason: .success,
              isPlateMatch: true,
              vehicleView: vehicleView,
              viewScore: result.mmr?.view?.score)
            return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
          } else if (detectedPlate.text.score ?? 0) >= 0.9
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
              rejectReason: .licensePlateMismatch)
            return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
          }
          // Low confidence or length mismatch – proceed to LLM
        }

        guard let mmr = result.mmr else {
          // No vehicle detection at all
          DebugPublisher.shared.error(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] No vehicle MMR data in API response")
          let outcome = VerificationOutcome(
            isMatch: false, description: "No vehicle detected", rejectReason: .apiError)
          return Just(outcome).setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        // Log MMR details for debugging
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] MMR data: make=\(mmr.make?.value ?? "unknown") model=\(mmr.model?.value ?? "unknown") color=\(mmr.color?.value ?? "unknown") view=\(mmr.view?.value ?? "unknown")"
        )
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] MMR confidence: make=\(String(format: "%.2f", mmr.make?.score ?? 0)) model=\(String(format: "%.2f", mmr.model?.score ?? 0)) color=\(String(format: "%.2f", mmr.color?.score ?? 0))"
        )

        if let plate = result.plate {
          DebugPublisher.shared.info(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] Plate detected: \(plate.text.value) (confidence=\(String(format: "%.2f", plate.text.score ?? 0)))"
          )
        }
        let vehicleView: Candidate.VehicleView = {
          switch mmr.view?.value {
          case "frontal": return .front
          case "rear", "back": return .rear
          case "side": return .side
          default: return .unknown
          }
        }()
        // Compute info quality and decide whether to call LLM
        let infoQ = {
          let makeScore = mmr.make?.score ?? 0
          let modelScore = mmr.model?.score ?? 0
          let colorScore = mmr.color?.score ?? 0
          return 0.5 * makeScore + 0.3 * modelScore + 0.2 * colorScore
        }()
        if infoQ < 0.4 {
          DebugPublisher.shared.warning(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] Insufficient information quality (infoQ=\(String(format: "%.2f", infoQ)), threshold=0.40)"
          )
          return Just(
            VerificationOutcome(
              isMatch: false, description: "Insufficient information",
              rejectReason: .insufficientInfo,
              vehicleView: vehicleView
            )
          )
          .setFailureType(to: Error.self)
          .eraseToAnyPublisher()
        }
        //        print(infoQ)
        // Even for low information quality, defer to LLM – it can respond with `maybe` which we map to a retryable reason.
        // Defer to LLM for make/model/color comparison regardless of info quality
        return self.callLLMForComparison(with: mmr, candidateId: candidateId)
      }
      .eraseToAnyPublisher()
  }

  private struct RecognitionResult {
    let mmr: MMR?
    let plate: Plate?
  }

  private func callTrafficEyeAPI(imageBytes: Data, candidateId: UUID) -> AnyPublisher<
    RecognitionResult, Error
  > {
    DebugPublisher.shared.info(
      "[TrafficEye][\(candidateId.uuidString.suffix(8))] Sending API request...")
    let boundary = "Boundary-\(UUID().uuidString)"
    var request = URLRequest(url: trafficEyeEndpoint)
    request.httpMethod = "POST"
    request.setValue(
      "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue(trafficEyeApiKey, forHTTPHeaderField: "apiKey")

    let requestBody = createMultipartBody(boundary: boundary, image: imageBytes)
    request.httpBody = requestBody

    return urlSession.dataTaskPublisherForRequest(request)
      .handleEvents(receiveOutput: { output in
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Received API response (\(output.data.count) bytes)"
        )
      })
      .tryMap { obj in
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Processing API response...")
        return obj.data
      }
      .decode(type: TrafficEyeResponse.self, decoder: jsonDecoder)
      .handleEvents(receiveOutput: { response in
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Successfully decoded API response")
      })
      .map { response -> RecognitionResult in
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Mapping response to RecognitionResult..."
        )
        let combinations = response.data?.combinations ?? []
        guard let first = combinations.first,
          let roadUser = first.roadUsers?.first,
          !combinations.isEmpty
        else {
          // No detections or missing data
          DebugPublisher.shared.info(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] No detections found in response")
          return RecognitionResult(mmr: nil, plate: nil)
        }
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Found detections, creating RecognitionResult"
        )
        return RecognitionResult(
          mmr: roadUser.mmr,
          plate: roadUser.plates?.max(by: { p1, p2 in
            p1.text.score ?? 0 < p2.text.score ?? 0
            // A predicate that returns true if its first argument should be ordered before its second argument [for increasing order]; otherwise, false.
          }))
      }
      .handleEvents(receiveCompletion: { completion in
        switch completion {
        case .finished:
          DebugPublisher.shared.info(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] API call completed successfully")
        case .failure(let err):
          DebugPublisher.shared.error(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] API call failed: \(err.localizedDescription)"
          )
        }
      })
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

  private func callLLMForComparison(with mmrResult: MMR, candidateId: UUID) -> AnyPublisher<
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
      Your job is to estimate the probability (0-1) that the ML prediction refers to the same car as described by the user, **and** provide a semantic_reason:
      - "match" if confident they are the same car.
      - "mismatch" if confident they are different.
      - "maybe" when uncertain or info is missing.
      You are necessary because there are differences in the technical api output and the plain language user input (like dashes, abbreviations, slight color differences)  and we still need a robust way to match the descriptions.
      Consider:
      - If the make and color are correct and the model is similar (and low-confidence), a match is likely.
      - If the api provides more information than the user, (e.g. API - Red honda civic User - Honda civic or Red civic) consider them to be equal
      - If the make is correct but the model is very different (e.g. Accord vs CR-V), it's likely not a match.
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
                      "Estimated probability (0-1) that the ML prediction refers to the same car as described by the user. Treat similar coloras (silver and gray) as equal"
                  ),
                  "semantic_reason": .init(
                    type: "string",
                    description:
                      "Match if confident they are the same car. Mismatch if confident they are different. Maybe when uncertain or info is missing.",
                    enumValues: ["match", "maybe", "mismatch"]
                  ),
                ], required: ["probability_match", "semantic_reason"]))
        )
      ], max_tokens: 50
    )
    var request = URLRequest(url: openAIEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONEncoder().encode(requestPayload)
    let _ = Date()
    return urlSession.dataTaskPublisherForRequest(request)
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
        struct LLMResult: Decodable {
          let probability_match: Double
          let semantic_reason: String
        }
        func infoQuality(from mmr: MMR) -> Double {
          let makeScore = mmr.make?.score ?? 0
          let modelScore = mmr.model?.score ?? 0
          let colorScore = mmr.color?.score ?? 0
          return 0.5 * makeScore + 0.3 * modelScore + 0.2 * colorScore
        }
        let args = try self.jsonDecoder.decode(LLMResult.self, from: data)
        let infoQ = infoQuality(from: mmrResult)
        let qualityLevel: String = infoQ >= 0.85 ? "high" : (infoQ >= 0.4 ? "medium" : "low")

        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] LLM comparison: probability=\(String(format: "%.2f", args.probability_match)) reason=\(args.semantic_reason)"
        )
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Quality metrics: infoQ=\(String(format: "%.2f", infoQ)) qualityLevel=\(qualityLevel)"
        )

        // Log the target text description for comparison
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Target description: '\(self.targetTextDescription)'"
        )
        var isMatch = false
        var rejectReason: RejectReason = .insufficientInfo
        if qualityLevel == "high" {
          // Use full decision table as before

          switch args.semantic_reason {
          case "match":
            isMatch = true
            rejectReason = .success
          case "maybe":
            isMatch = false
            rejectReason = .lowConfidence
          default:
            isMatch = false
            rejectReason = .wrongModelOrColor
          }
        } else {  // medium quality
          switch args.semantic_reason {
          case "match":
            isMatch = true
            rejectReason = .success
          default:
            isMatch = false
            rejectReason = .insufficientInfo
          }
        }
        let vehicleView: Candidate.VehicleView = {
          switch mmrResult.view?.value.lowercased() {
          case "frontal": return .front
          case "rear", "back": return .rear
          case "side": return .side
          default: return .unknown
          }
        }()
        let outcome = VerificationOutcome(
          isMatch: isMatch,
          description:
            "\(mmrResult.color?.value ?? "") \(mmrResult.make?.value ?? "") \(mmrResult.model?.value ?? "")",
          rejectReason: rejectReason,
          vehicleView: vehicleView,
          viewScore: mmrResult.view?.score
        )

        if isMatch {
          DebugPublisher.shared.success(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] MATCH : \(mmrResult.color?.value ?? "") \(mmrResult.make?.value ?? "") \(mmrResult.model?.value ?? "") (probability=\(String(format: "%.2f", args.probability_match)))"
          )
        } else {
          DebugPublisher.shared.error(
            "[TrafficEye][\(candidateId.uuidString.suffix(8))] REJECT: \(rejectReason.rawValue) (probability=\(String(format: "%.2f", args.probability_match)), semantic_reason=\(args.semantic_reason))"
          )
        }

        let latency = Date().timeIntervalSince(self.lastVerifiedDate)
        DebugPublisher.shared.info(
          "[TrafficEye][\(candidateId.uuidString.suffix(8))] Verification completed in \(String(format: "%.3f", latency))s"
        )
        return outcome
      }
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    return Date().timeIntervalSince(lastVerifiedDate)
  }
}
