//  ParatransitDetector.swift
//  thing-finder
//
//  Decides from the user's vehicle description whether the search is for a
//  service vehicle such as a taxi, bus or paratransit van (verified by
//  AdvancedLLMVerifier, which reads colors, route numbers and logos) rather than
//  a car identified by make and model (hybrid verifier, TrafficEye first).
//  Classified by the LLM through the API proxy; there is no offline fallback.

import Foundation

struct ParatransitDetector {
  let proxy: APIProxy
  let session: URLSessionProtocol

  init(proxy: APIProxy = .shared, session: URLSessionProtocol = URLSession.shared) {
    self.proxy = proxy
    self.session = session
  }

  private static let tool = Tool(
    function: Function(
      name: "classify_vehicle_request",
      description: "Classify what kind of vehicle the user is waiting for.",
      parameters: FunctionParameters(
        type: "object",
        properties: [
          "category": FunctionProperty(
            type: "string",
            description:
              "make_model_car: a private car (rideshare such as Uber or Lyft) identified by make, model, color or plate. "
              + "service_vehicle: any vehicle identified by something other than its make and model: a taxi, bus, "
              + "paratransit van, shuttle or similar fleet vehicle, recognized by its color scheme, route number, "
              + "agency, logo, service name or other markings.",
            enumValues: ["make_model_car", "service_vehicle"]
          )
        ],
        required: ["category"]
      )
    )
  )

  private struct Result: Decodable {
    let category: String
  }

  func isParatransit(description: String) async throws -> Bool {
    var req = URLRequest(url: proxy.chatCompletionsURL)
    req.httpMethod = "POST"
    req.timeoutInterval = 10
    proxy.authorize(&req)
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let chat = ChatCompletionRequest(
      model: ChatCompletionRequest.verifierModel,
      messages: [
        Message(
          role: "system",
          content: [
            MessageContent(
              text: "Classify the vehicle the user is waiting for from their description.")
          ]),
        Message(role: "user", content: [MessageContent(text: description)]),
      ],
      tools: [Self.tool],
      max_completion_tokens: 50
    )
    req.httpBody = try JSONEncoder().encode(chat)

    var output: (data: Data, response: URLResponse)?
    for try await value in session.dataTaskPublisherForRequest(req).values {
      output = value
      break
    }
    guard let data = output?.data else { throw URLError(.badServerResponse) }

    let resp = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    guard let args = resp.choices.first?.message.tool_calls?.first?.function.arguments else {
      throw URLError(.cannotParseResponse)
    }
    let result = try JSONDecoder().decode(Result.self, from: Data(args.utf8))
    return result.category == "service_vehicle"
  }
}
