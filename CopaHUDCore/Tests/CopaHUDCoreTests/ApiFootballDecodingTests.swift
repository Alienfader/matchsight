import XCTest
@testable import CopaHUDCore

/// Decodes the recorded-shape JSON resources end-to-end into the the contract
/// contract types and asserts real field values — the decoder is the part most
/// likely to drift from API-Football's wire format, so it is exercised hard.
final class ApiFootballDecodingTests: XCTestCase {

  // MARK: helpers

  private func loadData(_ resource: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: resource, withExtension: "json"),
      "missing test resource \(resource).json")
    return try Data(contentsOf: url)
  }

  private func decode<T: Decodable>(_ type: ApiResponse<T>.Type, from resource: String) throws -> ApiResponse<T> {
    try JSONDecoder().decode(ApiResponse<T>.self, from: loadData(resource))
  }

  // MARK: fixtures

  func testFixtureTeamLogoDecoded() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-fixtures")
    let fixture = try XCTUnwrap(env.response.first).toFixture()
    XCTAssertEqual(fixture.home.logoURL?.absoluteString, "https://media.api-sports.io/football/teams/6.png")
    XCTAssertNil(fixture.home.code, "fixture payloads carry no team code")
  }

  func testFixturesDecodeIntoContract() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-fixtures")
    XCTAssertTrue(env.errors.isEmpty)
    let fixtures = env.response.map { $0.toFixture() }
    XCTAssertEqual(fixtures.count, 2)

    let bra = fixtures[0]
    XCTAssertEqual(bra.id, 1001)
    XCTAssertEqual(bra.home, Team(id: 6, name: "Brazil"))
    XCTAssertEqual(bra.away, Team(id: 26, name: "Argentina"))
    XCTAssertEqual(bra.groupLabel, "Group Stage - 1")
    XCTAssertEqual(bra.competition, "World Cup", "country 'World' is a placeholder — name only")
    XCTAssertEqual(bra.venue, "MetLife Stadium")
    XCTAssertEqual(bra.status, .notStarted)
    // 2026-06-11T16:00:00+00:00
    XCTAssertEqual(bra.kickoff, Date(timeIntervalSince1970: 1781193600))

    XCTAssertEqual(fixtures[1].home, Team(id: 2, name: "France"))
    XCTAssertEqual(fixtures[1].away, Team(id: 25, name: "Germany"))
  }

  // MARK: live snapshot

  func testLiveSnapshotDecodesScoreClockStatus() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-live")
    let snap = try XCTUnwrap(env.response.first).toSnapshot()
    XCTAssertEqual(snap.fixtureId, 1001)
    XCTAssertEqual(snap.score, ScoreLine(home: 2, away: 1))
    XCTAssertEqual(snap.status, .secondHalf)
    XCTAssertEqual(snap.elapsedMinutes, 67)
    XCTAssertNil(snap.possessionHome)
    XCTAssertEqual(snap.groupLabel, "Group Stage - 1")
  }

  func testNullGoalsBeforeKickoffBecomeZeroZero() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-fixtures")
    let snap = try XCTUnwrap(env.response.first).toSnapshot()
    XCTAssertEqual(snap.score, ScoreLine(home: 0, away: 0))
    XCTAssertNil(snap.elapsedMinutes)
  }

  // MARK: events + kind mapping

  func testEventsMapEveryKind() throws {
    let env = try decode(ApiResponse<EventDTO>.self, from: "apifootball-events")
    let events = env.response.map { $0.toEvent(fixtureId: 1001) }
    XCTAssertEqual(events.count, 8)

    XCTAssertEqual(events[0].kind, .goal(.normal))
    XCTAssertEqual(events[0].player, "Raphinha")
    XCTAssertEqual(events[0].assist, "Vinícius Júnior")
    XCTAssertEqual(events[0].team, Team(id: 6, name: "Brazil"))

    XCTAssertEqual(events[1].kind, .goal(.penalty))
    XCTAssertEqual(events[2].kind, .card(.yellow))
    XCTAssertEqual(events[3].kind, .card(.red))            // "Red Card"
    XCTAssertEqual(events[4].kind, .card(.red))            // "Second Yellow card"
    XCTAssertEqual(events[5].kind, .substitution)
    XCTAssertEqual(events[6].kind, .varDecision(detail: "Goal cancelled"))
    XCTAssertEqual(events[6].extraMinute, 2)
    XCTAssertEqual(events[7].kind, .unknown(type: "Whistle", detail: "Cooling Break"))
  }

  func testStableIdSynthesisIsDeterministic() throws {
    let first = try decode(ApiResponse<EventDTO>.self, from: "apifootball-events")
      .response.map { $0.toEvent(fixtureId: 1001) }
    let second = try decode(ApiResponse<EventDTO>.self, from: "apifootball-events")
      .response.map { $0.toEvent(fixtureId: 1001) }
    // Same JSON decoded twice → identical ids (re-poll dedup contract).
    XCTAssertEqual(first.map(\.id), second.map(\.id))
    // Spot-check the exact synthesized shape for the opening goal.
    XCTAssertEqual(first[0].id, "1001-23+0-6-Goal-Normal Goal-276")
    // Two different events → different ids.
    XCTAssertNotEqual(first[0].id, first[1].id)
    // All ids unique.
    XCTAssertEqual(Set(first.map(\.id)).count, first.count)
  }

  func testStableIdUsesExtraMinute() {
    let base = EventID.synthesize(fixtureId: 1, minute: 90, extraMinute: nil,
                                  teamId: 6, rawType: "Goal", rawDetail: "Normal Goal", playerId: 7)
    let extra = EventID.synthesize(fixtureId: 1, minute: 90, extraMinute: 3,
                                   teamId: 6, rawType: "Goal", rawDetail: "Normal Goal", playerId: 7)
    XCTAssertEqual(base, "1-90+0-6-Goal-Normal Goal-7")
    XCTAssertEqual(extra, "1-90+3-6-Goal-Normal Goal-7")
    XCTAssertNotEqual(base, extra)
  }

  // MARK: lineups

  func testLineupsDecode() throws {
    let env = try decode(ApiResponse<LineupDTO>.self, from: "apifootball-lineups")
    let lineups = env.response.map { $0.toLineup(fixtureId: 1001) }
    XCTAssertEqual(lineups.count, 2)

    let brazil = lineups[0]
    XCTAssertEqual(brazil.team, Team(id: 6, name: "Brazil"))
    XCTAssertEqual(brazil.formation, "4-3-3")
    XCTAssertEqual(brazil.startXI.count, 11)
    XCTAssertEqual(brazil.coach, "Dorival Júnior")
    XCTAssertEqual(brazil.startXI[0].name, "Alisson")
    XCTAssertEqual(brazil.startXI[0].number, 1)
    XCTAssertEqual(brazil.startXI[0].position, "G")
    XCTAssertEqual(brazil.startXI[0].grid, "1:1")

    XCTAssertEqual(lineups[1].formation, "4-4-2")
    XCTAssertEqual(lineups[1].coach, "Lionel Scaloni")
  }

  // MARK: statistics / possession

  func testPossessionParsesLeniently() throws {
    let env = try decode(ApiResponse<StatisticsDTO>.self, from: "apifootball-statistics")
    XCTAssertEqual(env.response.count, 2)
    let home = try XCTUnwrap(env.response.first { $0.team.id == 6 })
    let away = try XCTUnwrap(env.response.first { $0.team.id == 26 })
    XCTAssertEqual(home.ballPossession, 65)   // "65%" → 65
    XCTAssertEqual(away.ballPossession, 35)
  }

  func testStatValueHandlesIntStringAndNull() throws {
    let ints = try JSONDecoder().decode([StatValue].self, from: Data("[65, \"35%\", null, \"foo\"]".utf8))
    XCTAssertEqual(ints[0].intValue, 65)
    XCTAssertEqual(ints[1].intValue, 35)
    XCTAssertNil(ints[2].intValue)
    XCTAssertNil(ints[3].intValue)
  }

  // MARK: error envelope (object, not array)

  func testErrorObjectClassifiesUnauthorized() throws {
    let json = """
    { "get": "fixtures", "parameters": {}, "errors": { "token": "Error/Missing application key. Go to https://www.api-football.com/documentation-v3 to get your key." }, "results": 0, "paging": { "current": 1, "total": 1 }, "response": [] }
    """
    let env = try JSONDecoder().decode(ApiResponse<FixtureDTO>.self, from: Data(json.utf8))
    XCTAssertFalse(env.errors.isEmpty)
    XCTAssertEqual(FeedErrorClassifier.feedError(for: env.errors), .unauthorized)
  }

  func testErrorObjectClassifiesQuota() throws {
    let json = """
    { "get": "fixtures", "parameters": {}, "errors": { "requests": "You have reached the request limit for the day. Upgrade your subscription." }, "results": 0, "paging": { "current": 1, "total": 1 }, "response": [] }
    """
    let env = try JSONDecoder().decode(ApiResponse<FixtureDTO>.self, from: Data(json.utf8))
    XCTAssertFalse(env.errors.isEmpty)
    XCTAssertEqual(FeedErrorClassifier.feedError(for: env.errors), .quotaExceeded)
  }

  func testEmptyErrorsArrayIsEmpty() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-fixtures")
    XCTAssertTrue(env.errors.isEmpty)
  }

  // MARK: player stats

  func testRealPlayerStatsDecode() throws {
    let env = try decode(ApiResponse<PlayersTeamDTO>.self, from: "apifootball-real-players")
    let stats = env.response.flatMap(\.playerStats)
    XCTAssertEqual(stats.count, 6)
    let mukiele = try XCTUnwrap(stats.first { $0.playerId == 1146 })
    XCTAssertEqual(mukiele, PlayerStats(playerId: 1146, passes: 24, shots: 1, tackles: 2, interceptions: 2))
  }

  func testNullCounterMeansZeroForAPlayerWhoPlayed() throws {
    // The feed sends `shots.total: null` for a 90-minute keeper with no shots.
    let env = try decode(ApiResponse<PlayersTeamDTO>.self, from: "apifootball-real-players")
    let roefs = try XCTUnwrap(env.response.flatMap(\.playerStats).first { $0.playerId == 194536 })
    XCTAssertEqual(roefs.shots, 0)
    XCTAssertEqual(roefs.passes, 22)
  }

  func testUnusedPlayerHasNoStats() throws {
    let json = """
    {"get":"fixtures/players","parameters":{},"errors":[],"results":1,"paging":{"current":1,"total":1},
     "response":[{"team":{"id":1,"name":"A"},"players":[{"player":{"id":9,"name":"Bench"},
       "statistics":[{"games":{"minutes":null},"shots":{"total":null},"passes":{"total":null},
                      "tackles":{"total":null,"interceptions":null}}]}]}]}
    """
    let env = try JSONDecoder().decode(ApiResponse<PlayersTeamDTO>.self, from: Data(json.utf8))
    XCTAssertEqual(env.response.flatMap(\.playerStats),
                   [PlayerStats(playerId: 9, passes: nil, shots: nil, tackles: nil, interceptions: nil)])
  }

  // MARK: predictions & captain

  func testRealPredictionDecodesThreeWayPercentages() throws {
    let env = try decode(ApiResponse<PredictionDTO>.self, from: "apifootball-real-prediction")
    XCTAssertEqual(env.response.first?.winProbability, WinProbability(home: 45, draw: 45, away: 10))
  }

  func testPredictionWithUnparseablePercentIsNil() throws {
    let json = """
    {"get":"predictions","parameters":{},"errors":[],"results":1,"paging":{"current":1,"total":1},
     "response":[{"predictions":{"percent":{"home":null,"draw":"45%","away":"10%"}}}]}
    """
    let env = try JSONDecoder().decode(ApiResponse<PredictionDTO>.self, from: Data(json.utf8))
    XCTAssertNil(env.response.first?.winProbability)
  }

  func testCaptainComesFromPlayerStats() throws {
    let json = """
    {"get":"fixtures/players","parameters":{},"errors":[],"results":1,"paging":{"current":1,"total":1},
     "response":[{"team":{"id":1,"name":"A"},"players":[
       {"player":{"id":5,"name":"Marquinhos"},"statistics":[{"games":{"minutes":90,"captain":true},"shots":{"total":0},"passes":{"total":50},"tackles":{"total":2,"interceptions":1}}]},
       {"player":{"id":6,"name":"Other"},"statistics":[{"games":{"minutes":90,"captain":false}}]}]}]}
    """
    let env = try JSONDecoder().decode(ApiResponse<PlayersTeamDTO>.self, from: Data(json.utf8))
    let stats = env.response.flatMap(\.playerStats)
    XCTAssertEqual(stats.first { $0.playerId == 5 }?.isCaptain, true)
    XCTAssertEqual(stats.first { $0.playerId == 6 }?.isCaptain, false)
  }
}
