import XCTest
@testable import CopaHUDCore

/// Verifies the scripted replay: pre-kickoff state, score/event progression on
/// the scaled clock, VAR overturn (a goal vanishing), and the 60× rehearsal
/// budget (90-minute match in 90 wall seconds). Deterministic via injected now.
final class MockFeedTests: XCTestCase {

  private final class Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
  }

  private let base = Date(timeIntervalSince1970: 1_000_000)
  private let followedId = 1489371
  private let otherId = 1002

  private func loadScript() throws -> MatchScript {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "mock-match-script", withExtension: "json"))
    return try MatchScript.load(from: try Data(contentsOf: url))
  }

  /// A feed plus a clock you advance with `at(seconds)`.
  private func makeFeed(speed: Double = 1.0) throws -> (MockFeed, Clock) {
    let clock = Clock(base)
    let feed = MockFeed(script: try loadScript(), speed: speed, now: { clock.date })
    return (feed, clock)
  }

  private func advance(_ clock: Clock, toMatchSeconds seconds: Double, speed: Double = 1.0) {
    clock.date = base.addingTimeInterval(seconds / speed)
  }

  // MARK: - script integrity

  func testScriptLoadsArsenalVsChelsea() throws {
    let script = try loadScript()
    XCTAssertEqual(script.fixture.id, followedId)
    XCTAssertEqual(script.fixture.home.name, "Arsenal")
    XCTAssertEqual(script.fixture.away.name, "Chelsea")
    XCTAssertEqual(script.fixture.groupLabel, "Premier League")
    XCTAssertEqual(script.lineups.count, 2)
    XCTAssertEqual(script.lineups[0].startXI.count, 11)
    XCTAssertEqual(script.other.id, otherId)
    XCTAssertEqual(script.keyframes.last?.score, MatchScript.ScriptScore(home: 3, away: 2))
  }

  // MARK: - pre-kickoff

  func testBeforeStartEverythingIsPreKickoff() async throws {
    let (feed, _) = try makeFeed()
    let snap = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(snap.status, .notStarted)
    XCTAssertEqual(snap.score, ScoreLine(home: 0, away: 0))
    XCTAssertNil(snap.elapsedMinutes)
    let events = try await feed.events(fixtureId: followedId)
    XCTAssertTrue(events.isEmpty)
  }

  func testAtKickoffScoreIsZeroZero() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 0)
    let snap = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(snap.score, ScoreLine(home: 0, away: 0))
    XCTAssertEqual(snap.status, .firstHalf)
  }

  // MARK: - progression

  func testAdvancingPastGoalReflectsScoreAndEvents() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 1100)   // just past the 18' (1080s) Saka goal
    let snap = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(snap.score, ScoreLine(home: 1, away: 0))
    XCTAssertEqual(snap.elapsedMinutes, 18)

    let events = try await feed.events(fixtureId: followedId)
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].kind, .goal(.normal))
    XCTAssertEqual(events[0].player, "B. Saka")
    // The script carries real player ids; the mock mapping must keep them or
    // demo-mode takeovers lose their headshots (field-found bug).
    XCTAssertEqual(events[0].playerId, 1460)
  }

  func testVarOverturnRemovesGoalAndCorrectsScore() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()

    // At 42' João Pedro's disallowed goal is live: 1-2, and the goal event is present.
    advance(clock, toMatchSeconds: 2530)
    let before = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(before.score, ScoreLine(home: 1, away: 2))
    let goal42Id = EventID.synthesize(fixtureId: followedId, minute: 42, extraMinute: nil,
                                      teamId: 49, rawType: "Goal", rawDetail: "Normal Goal",
                                      playerId: 10329)
    let eventsBefore = try await feed.events(fixtureId: followedId)
    XCTAssertTrue(eventsBefore.contains { $0.id == goal42Id })

    // At 44' VAR overturns it: score back to 1-1, the goal event is GONE,
    // a VAR decision appears in its place.
    advance(clock, toMatchSeconds: 2650)
    let after = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(after.score, ScoreLine(home: 1, away: 1))
    let eventsAfter = try await feed.events(fixtureId: followedId)
    XCTAssertFalse(eventsAfter.contains { $0.id == goal42Id }, "overturned goal must vanish")
    XCTAssertTrue(eventsAfter.contains { if case .varDecision = $0.kind { return true }; return false })
  }

  func testYellowCardAppears() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 2200)   // past 36' Zubimendi yellow
    let events = try await feed.events(fixtureId: followedId)
    XCTAssertTrue(events.contains { $0.kind == .card(.yellow) && $0.player == "Martín Zubimendi" })
  }

  func testHalfTimeAndFullTimeStatuses() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()

    advance(clock, toMatchSeconds: 2700)   // HT
    let ht = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(ht.status, .halfTime)

    advance(clock, toMatchSeconds: 5400)   // FT
    let ft = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(ft.status, .finished)
    XCTAssertEqual(ft.score, ScoreLine(home: 3, away: 2))
  }

  func testStableIdsMatchSynthesisRule() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 1100)
    let events = try await feed.events(fixtureId: followedId)
    XCTAssertEqual(events.first?.id, "1489371-18+0-42-Goal-Normal Goal-1460")
    // Re-poll → identical ids.
    let again = try await feed.events(fixtureId: followedId)
    XCTAssertEqual(events.map(\.id), again.map(\.id))
  }

  // MARK: - 60× rehearsal budget

  func testSpeed60CompletesNinetyMinutesInNinetyWallSeconds() async throws {
    let (feed, clock) = try makeFeed(speed: 60)
    feed.start()

    // 89 wall seconds in → not yet full time.
    clock.date = base.addingTimeInterval(89)
    let near = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertFalse(near.status.isFinished)

    // 90 wall seconds in → 5400 match seconds → full time.
    clock.date = base.addingTimeInterval(90)
    let done = try await feed.liveSnapshot(fixtureId: followedId)
    XCTAssertEqual(done.status, .finished)
    XCTAssertEqual(done.score, ScoreLine(home: 3, away: 2))
  }

  // MARK: - cross-match (other) timeline

  func testOtherMatchProgressesAndAppearsInOtherLive() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()

    advance(clock, toMatchSeconds: 3100)   // other match at 50' → 2-0
    let live = try await feed.otherLive()
    XCTAssertEqual(live.count, 1)
    XCTAssertEqual(live[0].fixtureId, otherId)
    XCTAssertEqual(live[0].score, ScoreLine(home: 2, away: 0))

    let otherEvents = try await feed.events(fixtureId: otherId)
    XCTAssertEqual(otherEvents.filter { if case .goal = $0.kind { return true }; return false }.count, 2)
  }

  func testOtherLiveEmptyWhenOtherMatchFinished() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 5400)   // both finished
    let live = try await feed.otherLive()
    XCTAssertTrue(live.isEmpty)
  }

  // MARK: - fixtures + lineups

  func testTodaysFixturesListsBothMatches() async throws {
    let (feed, _) = try makeFeed()
    let fixtures = try await feed.todaysFixtures()
    XCTAssertEqual(Set(fixtures.map(\.id)), [followedId, otherId])
  }

  func testLineupsReturnedForFollowedMatch() async throws {
    let (feed, _) = try makeFeed()
    let lineups = try await feed.lineups(fixtureId: followedId)
    XCTAssertEqual(lineups.count, 2)
    XCTAssertEqual(lineups[0].formation, "4-3-3")
    XCTAssertEqual(lineups[0].startXI.count, 11)
    XCTAssertEqual(lineups[0].coach, "Mikel Arteta")
  }

  // MARK: - substitutions (AI analyst demo: "what changed after the sub?")

  private func substitutions(_ events: [MatchEvent]) -> [MatchEvent] {
    events.filter { $0.kind == .substitution }
  }

  func testScriptHasThreeSubstitutionsByFullTime() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 5400)
    let subs = substitutions(try await feed.events(fixtureId: followedId))
    XCTAssertEqual(subs.map(\.minute), [63, 72, 80])
  }

  func testSubstitutionVisibleAt63() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 3780)
    let subs = substitutions(try await feed.events(fixtureId: followedId))
    XCTAssertEqual(subs.count, 1)
    XCTAssertEqual(subs.first?.player, "M. Ødegaard")     // off
    XCTAssertEqual(subs.first?.assist, "Mikel Merino")    // on
    XCTAssertEqual(subs.first?.team.name, "Arsenal")
  }

  func testSubstitutionBeatsAt63_72_80() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 5400)
    let subs = substitutions(try await feed.events(fixtureId: followedId))
    XCTAssertEqual(subs.map(\.minute), [63, 72, 80])
    XCTAssertEqual(subs.map(\.team.id), [42, 49, 42])
  }

  func testScriptTeamsCarryCrests() async throws {
    let (feed, _) = try makeFeed()
    let fixtures = try await feed.todaysFixtures()
    let fixture = try XCTUnwrap(fixtures.first { $0.id == followedId })
    XCTAssertEqual(fixture.home.logoURL?.absoluteString, "https://media.api-sports.io/football/teams/42.png")
    XCTAssertEqual(fixture.away.logoURL?.absoluteString, "https://media.api-sports.io/football/teams/49.png")
  }

  func testDemoFixturesAreLabelledPremierLeagueDemo() async throws {
    let (feed, _) = try makeFeed()
    let fixtures = try await feed.todaysFixtures()
    XCTAssertEqual(Set(fixtures.compactMap(\.competition)), ["Premier League (demo)"])
  }

  func testPrimaryTeamIdsAreArsenalAndChelsea() throws {
    let (feed, _) = try makeFeed()
    XCTAssertEqual(feed.primaryTeamIds, Set([42, 49]))
  }

  func testScriptSubstitutionsAreConsistent() async throws {
    let (feed, clock) = try makeFeed()
    feed.start()
    advance(clock, toMatchSeconds: 5400)
    let events = try await feed.events(fixtureId: followedId)
    for sub in substitutions(events) {
      let off = try XCTUnwrap(sub.player)
      let later = events.filter { $0.kind != .substitution && $0.minute > sub.minute }
      XCTAssertFalse(later.contains { $0.player == off || $0.assist == off },
                     "\(off) acts after being subbed off at \(sub.minute)'")
    }
  }
}
