import XCTest
@testable import CopaHUDCore

/// Exercises `MetaModelInsightService` with a `URLProtocol` stub: the exact
/// Meta Model API request shape, response parsing through the validator, and
/// typed error mapping. Zero real network traffic.
final class MetaModelInsightServiceTests: XCTestCase {

  // MARK: - URLProtocol stub

  final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    /// Seconds to wait before answering — drives the cancellation test.
    static var delay: TimeInterval = 0

    static func reset() {
      handler = nil
      delay = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      let respond = { [self] in
        guard let handler = StubURLProtocol.handler else {
          client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
          return
        }
        do {
          let (response, data) = try handler(request)
          client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
          client?.urlProtocol(self, didLoad: data)
          client?.urlProtocolDidFinishLoading(self)
        } catch {
          client?.urlProtocol(self, didFailWithError: error)
        }
      }
      if StubURLProtocol.delay > 0 {
        DispatchQueue.global().asyncAfter(deadline: .now() + StubURLProtocol.delay, execute: respond)
      } else {
        respond()
      }
    }

    override func stopLoading() {}
  }

  override func setUp() {
    super.setUp()
    StubURLProtocol.reset()
  }

  override func tearDown() {
    StubURLProtocol.reset()
    super.tearDown()
  }

  // MARK: - Helpers

  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func service(apiKey: String? = "test-key",
                       baseURL: URL = URL(string: "https://api.meta.ai/v1")!) -> MetaModelInsightService {
    var config = MetaModelConfig()
    config.apiKey = apiKey
    config.baseURL = baseURL
    return MetaModelInsightService(config: config, session: makeSession())
  }

  private func context() -> MatchInsightContext {
    let brazil = Team(id: 6, name: "Brazil")
    let snap = MatchSnapshot(fixtureId: 1, home: brazil, away: Team(id: 31, name: "Morocco"),
                             score: ScoreLine(home: 2, away: 1), status: .secondHalf,
                             elapsedMinutes: 67, possessionHome: nil, groupLabel: nil,
                             kickoff: Date(timeIntervalSince1970: 0))
    let goal = MatchEvent(id: "g", fixtureId: 1, minute: 18, extraMinute: nil, team: brazil,
                          player: "Raphinha", assist: nil, kind: .goal(.normal))
    return MatchInsightContext.build(snapshot: snap, events: [goal], lineups: [],
                                     stats: nil, isScripted: false)
  }

  private let validContent =
    #"{"title":"BRAZIL IN FRONT","body":"Brazil lead 2–1 after Raphinha's 18th-minute goal.","basis":"observed","factIds":["F1"]}"#

  /// Stubs one chat-completions answer carrying `content` as the message.
  private func stubCompletion(content: String, finishReason: String = "stop", status: Int = 200) {
    let envelope: [String: Any] = [
      "id": "chatcmpl-test", "object": "chat.completion", "model": "muse-spark-1.3",
      "choices": [["index": 0, "message": ["role": "assistant", "content": content],
                   "finish_reason": finishReason]],
    ]
    let data = try! JSONSerialization.data(withJSONObject: envelope)
    StubURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
    }
  }

  private func stubStatus(_ status: Int) {
    StubURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
       Data(#"{"error":{"message":"nope"}}"#.utf8))
    }
  }

  private func expectError(_ expected: InsightError,
                           file: StaticString = #filePath, line: UInt = #line) async {
    do {
      _ = try await service().insight(for: context(), question: .matchStory)
      XCTFail("expected \(expected)", file: file, line: line)
    } catch {
      XCTAssertEqual(error as? InsightError, expected, file: file, line: line)
    }
  }

  // MARK: - Request

  func testRequestShape() throws {
    let request = try service().makeRequest(context: context(), question: .formation)
    XCTAssertEqual(request.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(
      JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    XCTAssertEqual(body["model"] as? String, "muse-spark-1.3")
    // Reasoning tokens count against this cap (live run 2026-10-26: 298 of
    // 300 went to reasoning → every answer truncated), so leave headroom.
    XCTAssertEqual(body["max_completion_tokens"] as? Int, 1200)
    XCTAssertEqual(body["reasoning_effort"] as? String, "minimal")
    let format = try XCTUnwrap(body["response_format"] as? [String: Any])
    XCTAssertEqual(format["type"] as? String, "json_schema")
    let schema = try XCTUnwrap(format["json_schema"] as? [String: Any])
    XCTAssertEqual(schema["strict"] as? Bool, true)
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
    XCTAssertEqual(messages[0]["role"] as? String, "system")
    XCTAssertTrue((messages[1]["content"] as? String ?? "").contains("F1: Score: Brazil 2–1 Morocco"))
  }

  func testNoAuthHeaderWhenKeyNil() throws {
    let request = try service(apiKey: nil, baseURL: URL(string: "https://proxy.example/v1")!)
      .makeRequest(context: context(), question: .matchStory)
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(request.url?.absoluteString, "https://proxy.example/v1/chat/completions")
  }

  func testCustomHeadersAreSent() throws {
    var config = MetaModelConfig()
    config.apiKey = nil
    config.baseURL = URL(string: "https://copahud-ai.example.workers.dev/v1")!
    config.headers = ["X-CopaHUD-Token": "t"]
    let request = try MetaModelInsightService(config: config, session: makeSession())
      .makeRequest(context: context(), question: .matchStory)
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-CopaHUD-Token"), "t")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(request.url?.absoluteString,
                   "https://copahud-ai.example.workers.dev/v1/chat/completions")
  }

  // MARK: - Response

  func testParsesValidInsight() async throws {
    stubCompletion(content: validContent)
    let insight = try await service().insight(for: context(), question: .matchStory)
    XCTAssertEqual(insight.source, .model)
    XCTAssertEqual(insight.title, "BRAZIL IN FRONT")
    XCTAssertEqual(insight.factIds, ["F1"])
  }

  func testFencedJSONContentIsAccepted() async throws {
    stubCompletion(content: "```json\n\(validContent)\n```")
    let insight = try await service().insight(for: context(), question: .matchStory)
    XCTAssertEqual(insight.basis, .observed)
  }

  func testHTTPErrorMapping() async {
    stubStatus(401); await expectError(.unauthorized)
    stubStatus(403); await expectError(.unauthorized)
    stubStatus(429); await expectError(.rateLimited)
    stubStatus(500); await expectError(.http(500, "nope"))
    stubStatus(504); await expectError(.timeout)
  }

  func testHTTPErrorKeepsAPIMessageOrBodySlice() async {
    StubURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
       Data(#"{"error":{"message":"reasoning_effort is not supported"}}"#.utf8))
    }
    await expectError(.http(400, "reasoning_effort is not supported"))
    StubURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!,
       Data(("bad gateway " + String(repeating: "x", count: 500)).utf8))
    }
    do {
      _ = try await service().insight(for: context(), question: .matchStory)
      XCTFail("expected http error")
    } catch InsightError.http(let code, let detail) {
      XCTAssertEqual(code, 502)
      XCTAssertTrue(detail?.hasPrefix("bad gateway") == true)
      XCTAssertLessThanOrEqual(detail?.count ?? 0, 200)
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testURLErrorCancelledWithoutTaskCancelIsNetwork() async {
    StubURLProtocol.handler = { _ in throw URLError(.cancelled) }
    do {
      _ = try await service().insight(for: context(), question: .matchStory)
      XCTFail("expected network error")
    } catch InsightError.network {
      // expected: not the caller's cancellation, so the app still shows its fallback
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testSpokenQuestionRejectsUncitedGeneralTactics() async {
    stubCompletion(content: #"{"title":"AGE","body":"Rodrygo is 25 years old.","basis":"general_tactics","factIds":[]}"#)
    do {
      _ = try await service().insight(for: context(), question: .spoken("How old is Rodrygo?"))
      XCTFail("expected invalid")
    } catch {
      XCTAssertEqual(error as? InsightError, .invalid(.missingFacts))
    }
    // The same uncited general answer is still fine for a preset question.
    stubCompletion(content: #"{"title":"4-3-3","body":"A 4-3-3 usually gives width up front.","basis":"general_tactics","factIds":[]}"#)
    let ok = try? await service().insight(for: context(), question: .formation)
    XCTAssertNotNil(ok)
  }

  func testSpokenPromptAsksForCitations() {
    XCTAssertTrue(InsightPrompt.user(context: context(), question: .spoken("Who will win?"))
      .contains("Cite at least one fact"))
  }

  func testTruncatedOutput() async {
    stubCompletion(content: #"{"title":"BRA"#, finishReason: "length")
    await expectError(.malformedResponse("truncated"))
  }

  func testNonJSONContentIsMalformed() async {
    stubCompletion(content: "Brazil look strong.")
    do {
      _ = try await service().insight(for: context(), question: .matchStory)
      XCTFail("expected malformedResponse")
    } catch InsightError.malformedResponse {
      // expected
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  func testInvalidInsightMapped() async {
    stubCompletion(content: #"{"title":"X","body":"Y.","basis":"observed","factIds":["F42"]}"#)
    await expectError(.invalid(.unknownFact("F42")))
  }

  func testCancellationPropagates() async {
    stubCompletion(content: validContent)
    StubURLProtocol.delay = 2
    let svc = service()
    let c = context()
    let start = Date()
    let task = Task { try await svc.insight(for: c, question: .matchStory) }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError, "got \(error)")
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
  }
}
