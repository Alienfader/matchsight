import XCTest
@testable import CopaHUDCore

/// Muse Voice Transcribe client: exact multipart request shape for
/// POST /v1/asr/transcribe, player-name keyword biasing, transcript parsing
/// and the shared InsightError mapping. Reuses the model-service URL stub.
final class MetaVoiceTranscriberTests: XCTestCase {
  private typealias Stub = MetaModelInsightServiceTests.StubURLProtocol

  override func setUp() { super.setUp(); Stub.reset() }
  override func tearDown() { Stub.reset(); super.tearDown() }

  private func transcriber(apiKey: String? = "test-key",
                           headers: [String: String] = [:]) -> MetaVoiceTranscriber {
    var config = MetaModelConfig()
    config.apiKey = apiKey
    config.headers = headers
    let session = URLSessionConfiguration.ephemeral
    session.protocolClasses = [Stub.self]
    return MetaVoiceTranscriber(config: config, session: URLSession(configuration: session))
  }

  private let wav = WAVEncoder.pcm16Mono([10, 20, 30])

  private func stub(status: Int, body: String) {
    Stub.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
       Data(body.utf8))
    }
  }

  private func contains(_ data: Data, _ text: String) -> Bool {
    data.range(of: Data(text.utf8)) != nil
  }

  func testRequestIsMultipartWithSettingsAndAudio() throws {
    let request = try transcriber().makeRequest(wav: wav, keywords: ["Paquetá", "Rodrygo"])
    XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/asr/transcribe")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
    XCTAssertTrue(type.hasPrefix("multipart/form-data; boundary="))
    let body = try XCTUnwrap(request.httpBody)
    XCTAssertTrue(contains(body, #"name="request""#))
    XCTAssertTrue(contains(body, "Content-Type: application/json"))
    XCTAssertTrue(contains(body, #""mode":"PUSH_TO_TALK""#))
    XCTAssertTrue(contains(body, #""model":"muse-voice-transcribe-1.0""#))
    XCTAssertTrue(contains(body, #""audioEncoding":"WAV""#))
    XCTAssertTrue(contains(body, "Paquet"))
    XCTAssertTrue(contains(body, #"name="audio"; filename="question.wav""#))
    XCTAssertTrue(contains(body, "Content-Type: audio/wav"))
    XCTAssertNotNil(body.range(of: wav))
  }

  func testKeywordsDedupedAndCapped() throws {
    let names = (1...60).map { "Player\($0 % 55)" }
    let keywords = MetaVoiceTranscriber.normalizedKeywords(names)
    XCTAssertEqual(keywords.count, 50)
    XCTAssertEqual(Set(keywords).count, 50)
    XCTAssertEqual(MetaVoiceTranscriber.normalizedKeywords(["  Rodrygo ", "Rodrygo", ""]), ["Rodrygo"])
  }

  func testParsesTranscript() async throws {
    stub(status: 200, body: #"{"sessionId":"s","transcript":"  Why did Brazil take Paquetá off? ","audioDurationMs":2100,"turns":[]}"#)
    let text = try await transcriber().transcribe(wav: wav, keywords: [])
    XCTAssertEqual(text, "Why did Brazil take Paquetá off?")
  }

  func testEmptyTranscriptIsReturnedTrimmed() async throws {
    stub(status: 200, body: #"{"sessionId":"s","transcript":"   ","audioDurationMs":900,"turns":[]}"#)
    let text = try await transcriber().transcribe(wav: wav, keywords: [])
    XCTAssertEqual(text, "")
  }

  func testErrorMapping() async {
    func expect(_ status: Int, _ body: String, _ expected: InsightError,
                line: UInt = #line) async {
      stub(status: status, body: body)
      do {
        _ = try await transcriber().transcribe(wav: wav, keywords: [])
        XCTFail("expected \(expected)", line: line)
      } catch {
        XCTAssertEqual(error as? InsightError, expected, line: line)
      }
    }
    await expect(401, "{}", .unauthorized)
    await expect(429, "{}", .rateLimited)
    await expect(400, #"{"error":{"message":"Unsupported WAV"}}"#, .http(400, "Unsupported WAV"))
  }

  func testUndecodableResponseIsMalformed() async {
    stub(status: 200, body: "not json")
    do {
      _ = try await transcriber().transcribe(wav: wav, keywords: [])
      XCTFail("expected malformedResponse")
    } catch InsightError.malformedResponse {
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testProxyHeaders() throws {
    var config = MetaModelConfig()
    config.apiKey = nil
    config.baseURL = URL(string: "https://copahud-ai.example.workers.dev/v1")!
    config.headers = ["X-CopaHUD-Token": "t"]
    let request = try MetaVoiceTranscriber(config: config).makeRequest(wav: wav, keywords: [])
    XCTAssertEqual(request.url?.absoluteString, "https://copahud-ai.example.workers.dev/v1/asr/transcribe")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-CopaHUD-Token"), "t")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
  }
}
