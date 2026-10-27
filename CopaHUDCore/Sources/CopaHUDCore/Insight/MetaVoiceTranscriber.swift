import Foundation

/// Speech → text for "ask the analyst by voice".
public protocol VoiceTranscriber: Sendable {
  func transcribe(wav: Data, keywords: [String]) async throws -> String
}

/// Muse Voice Transcribe via Meta Model API (`POST {baseURL}/asr/transcribe`,
/// multipart: `request` JSON settings + `audio` WAV). `keywords` biases
/// recognition toward this match's player and team names. Shares
/// `MetaModelConfig` (base URL, key or proxy headers, timeout) with the
/// insight service, and the same `InsightError` vocabulary.
public struct MetaVoiceTranscriber: VoiceTranscriber {
  public static let model = "muse-voice-transcribe-1.0"
  static let maxKeywords = 50

  private let config: MetaModelConfig
  private let session: URLSession

  public init(config: MetaModelConfig, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  public func transcribe(wav: Data, keywords: [String]) async throws -> String {
    let request = try makeRequest(wav: wav, keywords: keywords)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError {
      if Task.isCancelled { throw CancellationError() }
      if error.code == .timedOut { throw InsightError.timeout }
      throw InsightError.network(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else {
      throw InsightError.network("non-HTTP response")
    }
    if let error = InsightError.from(status: http.statusCode, data: data) { throw error }

    struct Response: Decodable { let transcript: String }
    do {
      return try JSONDecoder().decode(Response.self, from: data).transcript
        .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw InsightError.malformedResponse("transcript: \(error.localizedDescription)")
    }
  }

  // MARK: - Request

  func makeRequest(wav: Data, keywords: [String]) throws -> URLRequest {
    let boundary = "CopaHUD-\(UUID().uuidString)"
    var request = URLRequest(url: config.baseURL.appendingPathComponent("asr/transcribe"))
    request.httpMethod = "POST"
    request.timeoutInterval = config.timeout
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let key = config.apiKey, !key.isEmpty {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    for (name, value) in config.headers {
      request.setValue(value, forHTTPHeaderField: name)
    }

    let settings: [String: Any] = [
      "model": Self.model,
      "audioEncoding": "WAV",
      "mode": "PUSH_TO_TALK",
      "keywords": Self.normalizedKeywords(keywords),
    ]
    let settingsJSON = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])

    var body = Data()
    func line(_ text: String) { body.append(Data((text + "\r\n").utf8)) }
    line("--\(boundary)")
    line(#"Content-Disposition: form-data; name="request""#)
    line("Content-Type: application/json")
    line("")
    body.append(settingsJSON); line("")
    line("--\(boundary)")
    line(#"Content-Disposition: form-data; name="audio"; filename="question.wav""#)
    line("Content-Type: audio/wav")
    line("")
    body.append(wav); line("")
    line("--\(boundary)--")
    request.httpBody = body
    return request
  }

  /// Trimmed, de-duplicated (order kept), at most `maxKeywords`.
  static func normalizedKeywords(_ keywords: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for raw in keywords {
      let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !k.isEmpty, seen.insert(k).inserted else { continue }
      out.append(k)
      if out.count == maxKeywords { break }
    }
    return out
  }
}

extension InsightError {
  /// Shared Meta Model API status mapping (chat completions + transcription):
  /// nil for 2xx.
  static func from(status: Int, data: Data) -> InsightError? {
    switch status {
    case 200..<300: return nil
    case 401, 403: return .unauthorized
    case 429: return .rateLimited
    case 504: return .timeout
    default: return .http(status, MetaModelInsightService.errorDetail(data))
    }
  }
}
