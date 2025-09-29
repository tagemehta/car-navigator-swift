import Combine
import Foundation

/*
// MARK: - Verifier Protocol and Outcome

public protocol ImageVerifier: AnyObject {
  var targetClasses: [String] { get }
  var targetTextDescription: String { get }
  func verify(imageData: String) -> AnyPublisher<VerificationOutcome, Error>
  func timeSinceLastVerification() -> TimeInterval
}

public struct VerificationOutcome {
  public let isMatch: Bool
}

// MARK: - OpenAI Chat Completion Models

public struct ChatCompletionRequest: Codable {
  let model: String
  let messages: [Message]
  let tools: [Tool]?

  public init(model: String, messages: [Message], tools: [Tool]? = nil) {
    self.model = model
    self.messages = messages
    self.tools = tools
  }
}

public struct Message: Codable {
  let role: String
  let content: [MessageContent]

  public init(role: String, content: [MessageContent]) {
    self.role = role
    self.content = content
  }
}

public enum MessageContent: Codable {
  case text(String)
  case imageUrl(String)

  private enum CodingKeys: String, CodingKey {
    case type, text, image_url
  }

  private struct ImageUrlPayload: Codable {
    let url: String
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
    case .imageUrl(let url):
      try container.encode("image_url", forKey: .type)
      try container.encode(ImageUrlPayload(url: url), forKey: .image_url)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    if type == "text" {
      self = .text(try container.decode(String.self, forKey: .text))
    } else if type == "image_url" {
      let payload = try container.decode(ImageUrlPayload.self, forKey: .image_url)
      self = .imageUrl(payload.url)
    } else {
      throw DecodingError.dataCorruptedError(
        forKey: .type, in: container, debugDescription: "Invalid message content type")
    }
  }
}

public struct Tool: Codable {
  let function: Function

  public init(function: Function) {
    self.function = function
  }
}

public struct Function: Codable {
  let name: String
  let description: String
  let parameters: Parameters

  public struct Parameters: Codable {
    let type: String
    let properties: [String: Property]
    let required: [String]
  }

  public struct Property: Codable {
    let type: String
  }

  public init(name: String, description: String, parameters: Parameters) {
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}
*/
