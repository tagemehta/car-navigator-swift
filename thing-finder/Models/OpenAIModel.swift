/// MARK - Request Structs
struct ChatCompletionRequest: Encodable {
  let model: String
  let messages: [Message]
  let tools: [Tool]
  let tool_choice: String = "required"
  let max_tokens: Int
}

struct Message: Encodable {
  let role: String
  let content: [MessageContent]
}

struct MessageContent: Encodable {
  let type: String
  let text: String?  // for "text"
  let image_url: [String: String]?  // for "image_url"

  init(text: String) {
    self.type = "text"
    self.text = text
    self.image_url = nil
  }

  init(imageURL: String) {
    self.type = "image_url"
    self.text = nil
    self.image_url = ["url": imageURL]
  }
}
struct Tool: Encodable {
  let type = "function"
  let function: Function
}
struct Function: Encodable {
  let name: String
  let description: String
  let parameters: FunctionParameters
  let strict = true
}

struct FunctionParameters: Encodable {
  let type: String
  let properties: [String: FunctionProperty]
  let required: [String]
  let additionalProperties = false
}

struct FunctionProperty: Encodable {
  let type: String
  let description: String
  /// Optional enumeration of allowed string values for this property, encoded as `enum` in JSON.
  let enumValues: [String]?
  private enum CodingKeys: String, CodingKey {
    case type, description
    case enumValues = "enum"
  }

  init(type: String, description: String, enumValues: [String]? = nil) {
    self.type = type
    self.description = description
    self.enumValues = enumValues
  }
}

/// MARK - Response Structs
struct ChatCompletionResponse: Decodable {
  let choices: [Choice]
}

struct Choice: Decodable {
  let message: ChoiceMessage
}

struct ChoiceMessage: Decodable {
  let content: String?
  let tool_calls: [ToolCall]?
  let refusal: String?
}
struct ToolCall: Decodable {
  let function: FunctionCall
}
struct FunctionCall: Decodable {
  let name: String
  let arguments: String  // You’ll decode this manually to `MatchResult`
}

struct MatchResult: Decodable {
  let match: Bool
  let confidence: Double
  /// Reason for rejection when `match == false`, matches LLMRejectReason enum values.
  let reason: String?
  /// Short natural-language description of the detected object, e.g. “blue Toyota Camry”.
  let description: String?
}
