import XCTest
@testable import CopaHUDCore

/// The mock is what demo mode and tests run against: deterministic, honest
/// about being a mock (source .mock), and cancellable like the real service.
final class MockMatchInsightServiceTests: XCTestCase {
  private func context() -> MatchInsightContext {
    let snap = MatchSnapshot(fixtureId: 1, home: Team(id: 6, name: "Brazil"),
                             away: Team(id: 31, name: "Morocco"),
                             score: ScoreLine(home: 1, away: 0), status: .firstHalf,
                             elapsedMinutes: 20, possessionHome: nil, groupLabel: nil,
                             kickoff: Date(timeIntervalSince1970: 0))
    return MatchInsightContext.build(snapshot: snap, events: [], lineups: [],
                                     stats: nil, isScripted: true)
  }

  func testMockReturnsTemplateMarkedMock() async throws {
    let c = context()
    let insight = try await MockMatchInsightService().insight(for: c, question: .matchStory)
    XCTAssertEqual(insight.source, .mock)
    XCTAssertEqual(insight.body, InsightTemplate.make(context: c).body)
  }

  func testMockFailure() async {
    do {
      _ = try await MockMatchInsightService(failure: .rateLimited)
        .insight(for: context(), question: .formation)
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? InsightError, .rateLimited)
    }
  }

  func testMockCancellation() async {
    let c = context()
    let start = Date()
    let task = Task {
      try await MockMatchInsightService(delay: .seconds(5)).insight(for: c, question: .matchStory)
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertLessThan(Date().timeIntervalSince(start), 1)
  }

  func testQuestionPromptsAreFixedCopy() {
    XCTAssertEqual(InsightQuestion.matchStory.prompt, "What is the story of this match so far?")
    XCTAssertEqual(InsightQuestion.formation.prompt,
                   "What do the two formations suggest about how each team is set up?")
    XCTAssertEqual(InsightQuestion.substitutionImpact.prompt,
                   "What did the most recent substitution change?")
    XCTAssertEqual(InsightQuestion.playerToWatch.prompt,
                   "Which player should I watch right now, based on the facts?")
  }

  // MARK: spoken questions (Muse Voice Transcribe → Muse Spark)

  func testPresetsOrder() {
    XCTAssertEqual(InsightQuestion.presets,
                   [.matchStory, .formation, .substitutionImpact, .playerToWatch])
  }

  func testSpokenQuestionTrimmedTo200() {
    let long = String(repeating: "why ", count: 75)            // 300 chars
    XCTAssertEqual(InsightQuestion.spoken(long).prompt.count, 200)
    XCTAssertEqual(InsightQuestion.spoken("  Why\n did   they sub? ").prompt, "Why did they sub?")
    XCTAssertEqual(InsightQuestion.spoken("x").label, "spoken")
    XCTAssertEqual(InsightQuestion.formation.label, "formation")
  }

  func testSpokenQuestionInUserPrompt() {
    let text = InsightPrompt.user(context: context(), question: .spoken("Why did they take Paquetá off?"))
    XCTAssertTrue(text.contains("Question (asked aloud by the fan): Why did they take Paquetá off?"))
    XCTAssertTrue(InsightPrompt.user(context: context(), question: .formation)
      .contains("Question: What do the two formations suggest"))
  }

  func testSystemPromptNamesMatchsight() {
    XCTAssertTrue(InsightPrompt.system.hasPrefix("You are Matchsight's soccer analyst."))
  }

  func testSystemPromptHasUnanswerableRule() {
    XCTAssertTrue(InsightPrompt.system.contains(
      "- If the question cannot be answered from the facts, say so in one short sentence and point to the most relevant fact."))
  }
}
