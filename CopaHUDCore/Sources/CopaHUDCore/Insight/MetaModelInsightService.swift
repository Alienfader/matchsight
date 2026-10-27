import Foundation

/// Meta Model API settings. `baseURL` is swappable so a key-holding proxy can
/// replace the direct endpoint without code changes.
public struct MetaModelConfig: Sendable, Equatable {
  public var baseURL: URL = URL(string: "https://api.meta.ai/v1")!
  public var model: String = "muse-spark-1.3"
  /// nil when calling through a proxy that holds the key.
  public var apiKey: String?
  public var timeout: TimeInterval = 8
  /// Includes reasoning tokens (~250 at "minimal"); the answer itself is ~60.
  public var maxCompletionTokens: Int = 1200
  public var temperature: Double = 0.3
  public var reasoningEffort: String? = "minimal"
  /// Extra request headers, e.g. the CopaHUD proxy's `X-CopaHUD-Token`.
  public var headers: [String: String] = [:]

  public init() {}
}

/// Generates insights with Meta's Muse Spark via the OpenAI-compatible
/// `/chat/completions` endpoint, constrained by a strict json_schema and
/// gated by `InsightValidator`.
public struct MetaModelInsightService: MatchInsightService {
  private let config: MetaModelConfig
  private let session: URLSession

  public init(config: MetaModelConfig, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  public func insight(for context: MatchInsightContext,
                      question: InsightQuestion) async throws -> MatchInsight {
    let request = try makeRequest(context: context, question: question)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      // Only the caller's own cancellation is a CancellationError; any other
      // `.cancelled` (proxy auth, invalidated session) is a failure that must
      // still reach the template fallback.
      if Task.isCancelled { throw CancellationError() }
      if error.code == .timedOut { throw InsightError.timeout }
      throw InsightError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw InsightError.network("non-HTTP response")
    }
    if let error = InsightError.from(status: http.statusCode, data: data) { throw error }

    let completion: ChatCompletion
    do {
      completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
    } catch {
      throw InsightError.malformedResponse("envelope: \(error.localizedDescription)")
    }
    guard let choice = completion.choices.first else {
      throw InsightError.malformedResponse("no choices")
    }
    if choice.finish_reason == "length" { throw InsightError.malformedResponse("truncated") }
    guard let content = choice.message.content else {
      throw InsightError.malformedResponse("empty content")
    }

    let raw: RawInsight
    do {
      raw = try JSONDecoder().decode(RawInsight.self, from: Data(Self.stripFences(content).utf8))
    } catch {
      throw InsightError.malformedResponse("content: \(error.localizedDescription)")
    }

    do {
      return try InsightValidator.validate(raw, context: context, source: .model,
                                           requireCitations: question.isSpoken)
    } catch let error as InsightValidationError {
      throw InsightError.invalid(error)
    }
  }

  // MARK: - Request

  func makeRequest(context: MatchInsightContext, question: InsightQuestion) throws -> URLRequest {
    var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let key = config.apiKey, !key.isEmpty {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    for (name, value) in config.headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    var body: [String: Any] = [
      "model": config.model,
      "messages": [
        ["role": "system", "content": InsightPrompt.system],
        ["role": "user", "content": InsightPrompt.user(context: context, question: question)],
      ],
      "temperature": config.temperature,
      "max_completion_tokens": config.maxCompletionTokens,
      "response_format": [
        "type": "json_schema",
        "json_schema": [
          "name": "match_insight",
          "strict": true,
          "schema": InsightPrompt.responseSchema(),
        ] as [String: Any],
      ] as [String: Any],
    ]
    if let effort = config.reasoningEffort { body["reasoning_effort"] = effort }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  /// The API's `{"error":{"message":…}}` text, else the first 200 characters
  /// of the body — enough to diagnose a rejected parameter on a live run.
  static func errorDetail(_ data: Data) -> String? {
    struct Envelope: Decodable {
      struct Body: Decodable { let message: String? }
      let error: Body?
    }
    if let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message {
      return message
    }
    let text = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : String(text.prefix(200))
  }

  /// Tolerates ```json … ``` wrapping even though the schema forbids it.
  static func stripFences(_ content: String) -> String {
    var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.hasPrefix("```") else { return s }
    if let newline = s.firstIndex(of: "\n") {
      s = String(s[s.index(after: newline)...])
    } else {
      s = String(s.dropFirst(3))
    }
    if s.hasSuffix("```") { s = String(s.dropLast(3)) }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Response DTOs (OpenAI-compatible envelope)

  private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable { let content: String? }
      let message: Message
      let finish_reason: String?
    }
    let choices: [Choice]
  }
}
