import XCTest
@testable import CopaHUDCore

/// Decodes JSON recorded from the LIVE API-Football v3 API (Pro key,
/// 2026-06-06) — the spec requires decoders proven against recorded real
/// JSON, not just docs-shaped fixtures. Reference match: Haiti 1–2 Peru,
/// international friendly, fixture 1544811 (national teams — the same data
/// shape the World Cup produces).
final class RealRecordedJSONTests: XCTestCase {

  private func decode<T: Decodable>(_ type: ApiResponse<T>.Type, from resource: String) throws -> ApiResponse<T> {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: resource, withExtension: "json"),
      "missing test resource \(resource).json")
    return try JSONDecoder().decode(ApiResponse<T>.self, from: try Data(contentsOf: url))
  }

  func testRealFixturesDayDecodes() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-real-fixtures")
    XCTAssertTrue(env.errors.isEmpty)
    let fixtures = env.response.map { $0.toFixture() }
    XCTAssertEqual(fixtures.count, 8)
    // Every real fixture must survive mapping with sane fields.
    for f in fixtures {
      XCTAssertGreaterThan(f.id, 0)
      XCTAssertFalse(f.home.name.isEmpty)
      XCTAssertFalse(f.away.name.isEmpty)
      XCTAssertNotEqual(f.status, .unknown, "real status short must map")
    }
    // Competition labels: "name · country", country dropped when "World".
    let competitions = Set(fixtures.compactMap(\.competition))
    XCTAssertTrue(competitions.contains("Primera B · Chile"), "got \(competitions)")
    XCTAssertTrue(competitions.contains("Friendlies"), "got \(competitions)")
  }

  func testRealSingleFixtureSnapshot() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-real-single")
    let snap = try XCTUnwrap(env.response.first).toSnapshot()
    XCTAssertEqual(snap.fixtureId, 1544811)
    XCTAssertEqual(snap.home.name, "Haiti")
    XCTAssertEqual(snap.away.name, "Peru")
    XCTAssertEqual(snap.score, ScoreLine(home: 1, away: 2))
    XCTAssertEqual(snap.status, .finished)
  }

  func testRealEventsDecodeAndSynthesizeStableIds() throws {
    let env = try decode(ApiResponse<EventDTO>.self, from: "apifootball-real-events")
    XCTAssertEqual(env.response.count, 24)
    let events = env.response.map { $0.toEvent(fixtureId: 1544811) }

    // 3 goals (1-2 final), all map to .goal(.normal) in this match.
    let goals = events.filter { if case .goal(.normal) = $0.kind { return true }; return false }
    XCTAssertEqual(goals.count, 3)
    // Real goal events carry the scorer's feed id → headshot URL resolves.
    for g in goals {
      XCTAssertNotNil(g.playerId, "real goal events carry player ids")
      XCTAssertNotNil(PlayerPhoto.url(playerId: g.playerId))
    }
    // Yellow cards map, none red in this match.
    XCTAssertTrue(events.contains { $0.kind == .card(.yellow) })
    XCTAssertFalse(events.contains { $0.kind == .card(.red) })
    // Real "Substitution N" details all collapse to .substitution.
    XCTAssertTrue(events.contains { $0.kind == .substitution })
    // Nothing real may fall through to a throw, and ids must be stable + unique
    // per distinct event.
    let ids = events.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count, "synthesized ids must be unique for distinct real events")
    let again = env.response.map { $0.toEvent(fixtureId: 1544811) }.map(\.id)
    XCTAssertEqual(ids, again, "synthesized ids must be stable across decodes")
  }

  func testRealLineupsDecode() throws {
    let env = try decode(ApiResponse<LineupDTO>.self, from: "apifootball-real-lineups")
    let lineups = env.response.map { $0.toLineup(fixtureId: 1544811) }
    XCTAssertEqual(lineups.count, 2)
    XCTAssertEqual(lineups.map(\.formation), ["4-4-2", "4-2-3-1"])
    for l in lineups {
      XCTAssertEqual(l.startXI.count, 11)
      XCTAssertNotNil(l.coach)
    }
  }

  func testRealStatisticsPossession() throws {
    let env = try decode(ApiResponse<StatisticsDTO>.self, from: "apifootball-real-statistics")
    XCTAssertEqual(env.response.count, 2)
    XCTAssertEqual(env.response[0].ballPossession, 42)
    XCTAssertEqual(env.response[1].ballPossession, 58)
  }

  func testRealStatisticsMapToTeamStats() throws {
    let env = try decode(ApiResponse<StatisticsDTO>.self, from: "apifootball-real-statistics")
    let home = env.response[0].teamStats
    XCTAssertEqual(home.possession, 42)
    // The stats page needs at least the shot counts from real data.
    XCTAssertNotNil(home.totalShots)
    XCTAssertNotNil(home.shotsOnGoal)
    XCTAssertNotNil(home.corners)
  }

  func testRealLiveAllDecodesEverySnapshot() throws {
    let env = try decode(ApiResponse<FixtureDTO>.self, from: "apifootball-real-live")
    XCTAssertEqual(env.response.count, 12)
    let snaps = env.response.map { $0.toSnapshot() }
    for s in snaps {
      XCTAssertTrue(s.status.isLive, "live=all fixtures must map to live statuses, got \(s.status)")
      XCTAssertNotNil(s.elapsedMinutes, "in-progress matches carry an elapsed minute")
    }
  }
}
