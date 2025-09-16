import Combine
import Foundation
import UIKit

public final class LLMVerifier: ImageVerifier {
  private var lastVerifiedDate = Date()
  private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
  private let jsonEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    return encoder
  }()
  private let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    return decoder
  }()
  private let apiKey = Bundle.main.infoDictionary!["OPENAI_API"] as! String

  public let targetClasses: [String]
  public let targetTextDescription: String
  private let confidenceThreshold: Double = 0.86
  init(targetClasses: [String], targetTextDescription: String) {
    self.targetClasses = targetClasses
    self.targetTextDescription = targetTextDescription
  }

  public func verify(image: UIImage) -> AnyPublisher<VerificationOutcome, Error> {
    guard let base64 = image.jpegData(compressionQuality: 1)?.base64EncodedString() else {
      return Fail(error: NSError(domain: "", code: 0, userInfo: nil)).eraseToAnyPublisher()
    }
    lastVerifiedDate = Date()
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let payload = ChatCompletionRequest(
      model: "gpt-4.1-mini",
      messages: [
        Message(
          role: "system",
          content: [
            MessageContent(
              text:
                """
                You are an expert automotive identification specialist with deep knowledge of car makes, models, and visual characteristics.

                Your task is to determine if the vehicle in the image matches the provided description with extremely high accuracy.

                EXPERTISE GUIDELINES:
                - Pay close attention to make-specific design elements (grilles, headlights, body lines)
                - Distinguish between similar models within the same manufacturer
                - Identify model years based on subtle design changes
                - Recognize trim levels from badging and exterior features
                - Differentiate body styles (sedan, SUV, crossover, hatchback, etc.)
                - Accurately assess color accounting for lighting conditions

                CRITICAL DETAILS TO VERIFY:
                1. Make (manufacturer) - e.g., Toyota, Honda, BMW
                2. Model - e.g., Camry, Civic, X5
                3. Body style - e.g., sedan, SUV, truck
                4. Color - accounting for lighting variations
                5. Distinctive features mentioned in the description

                For ride-sharing identification, a partial match on make/model/color is often sufficient even if minor details differ.

                Respond strictly in JSON format as per the provided schema.
                You are doing this for a blind audience in an app that helps them navigate to objects.
                Accuracy is mission critical. Err on the side of caution.
                """
            )
          ]),
        Message(
          role: "user",
          content: [
            MessageContent(
              text:
                "Does this image, focusing on \(targetClasses.joined(separator: ", or ")), match the following description? \(targetTextDescription)"
            ),
            MessageContent(imageURL: "data:image/png;base64,\(base64)"),
          ]),
      ],
      tools: [
        Tool(
          function: Function(
            name: "match_object",
            description: "Determines if the image matches the given description.",
            parameters: FunctionParameters(
              type: "object",
              properties: [
                "match": FunctionProperty(
                  type: "boolean", description: "Indicates if the image matches the description."),
                "confidence": FunctionProperty(
                  type: "number",
                  description: "What is the probability (confidence) that this is a match?"),
                "reason": FunctionProperty(
                  type: "string",
                  description:
                    "If match=false, why not? One enum value. If match=true, this should be 'success'. If there isn't enough information to make a decision, this should be 'ambigous.' Returning unclear/ambiguous is better than a false positive, we can always send again from a different angle",
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
                  description:
                    "Short natural-language description of the object eg. [color, make, model]"),
              ],
              required: ["match", "confidence", "description", "reason"]
            )
          ))
      ],
      max_tokens: 100
    )

    do {
      request.httpBody = try jsonEncoder.encode(payload)
    } catch {
      return Fail(error: error).eraseToAnyPublisher()
    }
    return URLSession.shared.dataTaskPublisher(for: request)
      .tryMap {
        //        print(String(data: $0.data, encoding: .utf8))
        return $0.data
      }
      .decode(type: ChatCompletionResponse.self, decoder: jsonDecoder)
      .tryMap { [weak self] response in

        if let argsString = response.choices.first?.message.tool_calls?[0].function.arguments {
          let argsData = argsString.data(using: .utf8)!
          let matchResult = try self!.jsonDecoder.decode(MatchResult.self, from: argsData)
          let rej: RejectReason? = matchResult.match ? nil : matchResult.reason == nil ? .apiError : RejectReason(rawValue: matchResult.reason!)
          print(matchResult.confidence)
          if matchResult.match && matchResult.confidence < self!.confidenceThreshold {
            return VerificationOutcome(
              isMatch: false, description: matchResult.description!, rejectReason: .lowConfidence)
          }
          let v = VerificationOutcome(
            isMatch: matchResult.match, description: matchResult.description!,
            rejectReason: rej)
          return v
        } else {
          return VerificationOutcome(isMatch: false, description: "", rejectReason: nil)
        }
      }
      .eraseToAnyPublisher()
  }

  public func timeSinceLastVerification() -> TimeInterval {
    return Date().timeIntervalSince(lastVerifiedDate)
  }
}
