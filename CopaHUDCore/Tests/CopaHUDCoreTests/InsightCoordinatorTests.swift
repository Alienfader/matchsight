import XCTest
@testable import CopaHUDCore

/// The coordinator owns every model call the app makes: when to ask, which
/// request wins, and what the glasses show when the model fails (the
/// template, never nothing). Driven here by a scripted service.
@MainActor
final class InsightCoordinatorTests: XCTestCase {

  /// Plays back queued answers; counts calls. Default answer: "DEFAULT".
  actor ScriptedService: MatchInsightService {
    enum Step: Sendable {
      case answer(String, delay: Duration = .zero)
      case fail(InsightError)
    }

    private var steps: [Step]
    private(set) var calls = 0

    init(_ steps: [Step] = []) { self.steps = steps }

    func insight(for context: MatchInsightContext,
                 question: InsightQuestion) async throws -> MatchInsight {
      calls += 1
      let step = steps.isEmpty ? .answer("DEFAULT") : steps.removeFirst()
      switch step {
      case let .answer(title, delay):
        try await Task.sleep(for: delay)
        return MatchInsight(title: title, body: "B", basis: .dataInference, factIds: ["F1"],
                            source: .model, fingerprint: context.fingerprint)
      case let .fail(error):
        throw error
      }
    }
  }

  private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  private func context(home: Int = 1, scripted: Bool = false,
                       fixtureId: Int = 1) -> MatchInsightContext {
    let snap = MatchSnapshot(fixtureId: fixtureId, home: Team(id: 6, name: "Brazil"),
                             away: Team(id: 31, name: "Morocco"),
                             score: ScoreLine(home: home, away: 0), status: .firstHalf,
                             elapsedMinutes: 20, possessionHome: nil, groupLabel: nil,
                             kickoff: t0)
    return MatchInsightContext.build(snapshot: snap, events: [], lineups: [],
                                     stats: nil, isScripted: scripted)
  }

  /// Mutable test clock shared with the coordinator.
  private final class Clock: @unchecked Sendable { var now: Date; init(_ d: Date) { now = d } }

  private func coordinator(_ service: ScriptedService, clock: Clock? = nil,
                           fixtureId: Int? = 1) -> InsightCoordinator {
    let clock = clock ?? Clock(t0)
    let c = InsightCoordinator(service: service, now: { clock.now })
    c.reset(fixtureId: fixtureId)
    return c
  }

  func testAutoRequestPublishesModelInsight() async {
    let service = ScriptedService([.answer("MODEL")])
    let c = coordinator(service)
    var published: [InsightState] = []
    c.onChange = { published.append($0) }
    c.contextChanged(context())
    XCTAssertTrue(c.state.isUpdating)
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.title, "MODEL")
    XCTAssertEqual(c.state.question, .matchStory)
    XCTAssertFalse(c.state.isUpdating)
    XCTAssertNil(c.state.lastError)
    XCTAssertEqual(published.first?.isUpdating, true)
    XCTAssertEqual(published.last, c.state)
  }

  func testFailureFallsBackToTemplateWithError() async {
    let c = coordinator(ScriptedService([.fail(.rateLimited)]))
    c.contextChanged(context())
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.source, .template)
    XCTAssertEqual(c.state.lastError, .rateLimited)
    XCTAssertFalse(c.state.isUpdating)
  }

  func testSameContextDoesNotCallServiceTwice() async {
    let service = ScriptedService()
    let c = coordinator(service)
    c.contextChanged(context())
    await c.currentTask?.value
    c.contextChanged(context())
    await c.currentTask?.value
    let calls = await service.calls
    XCTAssertEqual(calls, 1)
  }

  func testAutoSkippedWhileRequestInFlight() async {
    let service = ScriptedService([.answer("SLOW", delay: .milliseconds(200))])
    let c = coordinator(service)
    c.contextChanged(context(home: 1))
    c.contextChanged(context(home: 2))
    await c.currentTask?.value
    let calls = await service.calls
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(c.state.insight?.title, "SLOW")
  }

  func testManualAskCancelsAuto() async {
    let service = ScriptedService([.answer("AUTO", delay: .seconds(2)), .answer("MANUAL")])
    let c = coordinator(service)
    let start = Date()
    c.contextChanged(context())
    c.ask(.formation, context: context())
    await c.currentTask?.value
    XCTAssertEqual(c.state.question, .formation)
    XCTAssertEqual(c.state.insight?.title, "MANUAL")
    XCTAssertFalse(c.state.isUpdating)
    XCTAssertLessThan(Date().timeIntervalSince(start), 1)
  }

  func testCachedAskSkipsService() async {
    let service = ScriptedService([.answer("FIRST")])
    let c = coordinator(service)
    c.ask(.formation, context: context())
    await c.currentTask?.value
    c.ask(.formation, context: context())
    XCTAssertNil(c.currentTask)
    XCTAssertFalse(c.state.isUpdating)
    XCTAssertEqual(c.state.insight?.title, "FIRST")
    let calls = await service.calls
    XCTAssertEqual(calls, 1)
  }

  func testResetDropsInFlightResult() async {
    let c = coordinator(ScriptedService([.answer("LATE", delay: .milliseconds(300))]))
    c.contextChanged(context())
    let task = c.currentTask
    c.reset(fixtureId: 2)
    await task?.value
    XCTAssertEqual(c.state, .idle)
  }

  func testSpokenAskShowsTheQuestionWhileThinkingThenWithTheAnswer() async {
    let c = coordinator(ScriptedService([.answer("TIMBER", delay: .milliseconds(50))]))
    c.ask(.spoken("who is Timber?"), context: context(scripted: true))
    XCTAssertEqual(c.state.hudContent,
                   InsightContent(title: "Thinking…", body: "", footer: "Muse Spark · scripted",
                                  question: "who is Timber?"))
    await c.currentTask?.value
    XCTAssertEqual(c.state.hudContent?.title, "TIMBER")
    XCTAssertEqual(c.state.hudContent?.question, "who is Timber?")
    XCTAssertEqual(c.state.hudContent?.footer, "Muse Spark · inferred · scripted")
  }

  func testPresetAndAutoAnswersHaveNoQuestionLine() async {
    let c = coordinator(ScriptedService())
    c.ask(.spoken("who scored?"), context: context())
    await c.currentTask?.value
    c.ask(.formation, context: context(home: 2))
    // A preset in flight keeps the spoken answer on screen, marked updating.
    XCTAssertEqual(c.state.hudContent?.question, "who scored?")
    XCTAssertEqual(c.state.hudContent?.footer, "Muse Spark · inferred · updating…")
    await c.currentTask?.value
    XCTAssertNil(c.state.hudContent?.question)
  }

  func testSetServiceClearsCache() async {
    let c = coordinator(ScriptedService([.answer("OLD")]))
    c.ask(.formation, context: context())
    await c.currentTask?.value
    let fresh = ScriptedService([.answer("NEW")])
    c.setService(fresh)
    c.ask(.formation, context: context())
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.title, "NEW")
  }

  func testHudContentFooter() {
    let model = MatchInsight(title: "T", body: "B", basis: .dataInference, factIds: ["F1"],
                             source: .model, fingerprint: "f")
    var state = InsightState.idle
    XCTAssertNil(state.hudContent)
    state.insight = model
    state.isScripted = true
    state.isUpdating = true
    XCTAssertEqual(state.hudContent,
                   InsightContent(title: "T", body: "B",
                                  footer: "Muse Spark · inferred · scripted · updating…"))
    state.insight = MatchInsight(title: "T", body: "B", basis: .observed, factIds: [],
                                 source: .template, fingerprint: "f")
    state.isScripted = false
    state.isUpdating = false
    XCTAssertEqual(state.hudContent?.footer, "Data only")
    state.insight = MatchInsight(title: "T", body: "B", basis: .observed, factIds: [],
                                 source: .mock, fingerprint: "f")
    XCTAssertEqual(state.hudContent?.footer, "Mock AI")
    state.insight = MatchInsight(title: "T", body: "B", basis: .generalKnowledge, factIds: [],
                                 source: .model, fingerprint: "f")
    XCTAssertEqual(state.hudContent?.footer, "Muse Spark · general knowledge")
  }

  // MARK: review fixes

  func testContextForOtherFixtureIsIgnored() async {
    let service = ScriptedService()
    let c = coordinator(service, fixtureId: 2)
    c.contextChanged(context(fixtureId: 1))      // stale loop of the old match
    c.ask(.formation, context: context(fixtureId: 1))
    XCTAssertNil(c.currentTask)
    XCTAssertEqual(c.state, .idle)
    let calls = await service.calls
    XCTAssertEqual(calls, 0)
    c.contextChanged(context(fixtureId: 2))      // the followed match still works
    await c.currentTask?.value
    XCTAssertNotNil(c.state.insight)
  }

  func testManualAnswerNotOverwrittenByAutoWithinMinInterval() async {
    let clock = Clock(t0)
    let service = ScriptedService([.answer("AUTO"), .answer("WATCH")])
    let c = coordinator(service, clock: clock)
    c.contextChanged(context(home: 1))
    await c.currentTask?.value
    clock.now = t0.addingTimeInterval(50)
    c.ask(.playerToWatch, context: context(home: 1))
    await c.currentTask?.value
    clock.now = t0.addingTimeInterval(60)          // data changed, only 10s after the ask
    c.contextChanged(context(home: 2))
    XCTAssertNil(c.currentTask)
    XCTAssertEqual(c.state.question, .playerToWatch)
    let calls = await service.calls
    XCTAssertEqual(calls, 2)
  }

  func testFailureRetriesAfterMinIntervalEvenWithSameData() async {
    let clock = Clock(t0)
    let service = ScriptedService([.fail(.timeout), .answer("RECOVERED")])
    let c = coordinator(service, clock: clock)
    c.contextChanged(context())
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.source, .template)
    clock.now = t0.addingTimeInterval(30)          // same data (e.g. half-time)
    c.contextChanged(context())
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.title, "RECOVERED")
  }

  func testUnauthorizedPausesAutoUntilServiceChanges() async {
    let clock = Clock(t0)
    let service = ScriptedService([.fail(.unauthorized)])
    let c = coordinator(service, clock: clock)
    c.contextChanged(context(home: 1))
    await c.currentTask?.value
    XCTAssertEqual(c.state.lastError, .unauthorized)
    clock.now = t0.addingTimeInterval(60)          // data changed, interval passed
    c.contextChanged(context(home: 2))
    XCTAssertNil(c.currentTask)
    let calls = await service.calls
    XCTAssertEqual(calls, 1)

    let fresh = ScriptedService([.answer("NEW KEY")])
    c.setService(fresh)
    c.contextChanged(context(home: 2))
    await c.currentTask?.value
    XCTAssertEqual(c.state.insight?.title, "NEW KEY")
  }
}
