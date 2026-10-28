import XCTest
@testable import CopaHUDCore

/// Demo mode's per-player figures: invented like the rest of the scripted
/// match, but every goal, assist, card and minute agrees with the script.
final class ScriptedPlayerStatsTests: XCTestCase {
  let ars = Team(id: 42, name: "Arsenal")
  let che = Team(id: 49, name: "Chelsea")

  private var lineups: [Lineup] {
    [Lineup(fixtureId: 1, team: ars, formation: "4-3-3", startXI: [
       LineupPlayer(name: "David Raya", number: 1, position: "G", grid: "1:1", playerId: 10),
       LineupPlayer(name: "D. Rice", number: 41, position: "M", grid: "3:2", playerId: 11),
       LineupPlayer(name: "M. Ødegaard", number: 8, position: "M", grid: "3:1", playerId: 12),
       LineupPlayer(name: "B. Saka", number: 7, position: "F", grid: "4:3", playerId: 13),
       LineupPlayer(name: "No Id", number: 99, position: "D", grid: "2:1"),
     ], coach: nil),
     Lineup(fixtureId: 1, team: che, formation: "4-2-3-1", startXI: [
       LineupPlayer(name: "E. Martínez", number: 1, position: "G", grid: "1:1", playerId: 20),
     ], coach: nil)]
  }

  private func event(_ minute: Int, _ team: Team, _ playerId: Int?, _ player: String,
                     assist: String? = nil, _ kind: MatchEvent.Kind) -> MatchEvent {
    MatchEvent(id: "\(minute)\(player)", fixtureId: 1, minute: minute, extraMinute: nil, team: team,
               player: player, playerId: playerId, assist: assist, kind: kind)
  }

  private var events: [MatchEvent] {
    [event(18, ars, 13, "B. Saka", assist: "D. Rice", .goal(.normal)),
     event(30, che, 20, "E. Martínez", .card(.yellow)),
     event(40, ars, 13, "B. Saka", .goal(.penalty)),
     event(50, ars, 13, "B. Saka", .goal(.missedPenalty)),
     event(55, che, nil, "Own", .goal(.ownGoal)),
     event(63, ars, nil, "M. Ødegaard", assist: "Mikel Merino", .substitution),
     event(70, che, 20, "E. Martínez", .card(.red))]
  }

  private func stats(elapsed: Int) -> [Int: PlayerStats] {
    ScriptedPlayerStats.make(lineups: lineups, events: events, elapsed: elapsed)
  }

  func testGoalsAssistsAndCardsFollowTheScript() {
    let s = stats(elapsed: 90)
    XCTAssertEqual(s[13]?.goals, 2, "normal and penalty count; a missed penalty doesn't")
    XCTAssertEqual(s[11]?.assists, 1)
    XCTAssertEqual(s[13]?.assists, 0)
    XCTAssertEqual(s[20]?.yellowCards, 1)
    XCTAssertEqual(s[20]?.redCards, 1)
    XCTAssertEqual(s[13]?.yellowCards, 0)
    XCTAssertGreaterThanOrEqual(s[13]?.shotsOnTarget ?? 0, 2)
    XCTAssertGreaterThanOrEqual(s[13]?.shots ?? 0, s[13]?.shotsOnTarget ?? 0)
  }

  func testMinutesStopAtSubstitutionAndRedCard() {
    let s = stats(elapsed: 90)
    XCTAssertEqual(s[13]?.minutes, 90)
    XCTAssertEqual(s[12]?.minutes, 63)
    XCTAssertEqual(s[20]?.minutes, 70)
    XCTAssertEqual(stats(elapsed: 40)[12]?.minutes, 40)
  }

  func testKeeperFiguresAndConcededWhileOnThePitch() {
    let s = stats(elapsed: 90)
    XCTAssertEqual(s[20]?.conceded, 2, "Saka's two; own goals are left out")
    XCTAssertEqual(s[10]?.conceded, 0)
    XCTAssertNotNil(s[10]?.saves)
    XCTAssertNil(s[13]?.saves)
    XCTAssertNil(s[13]?.conceded)
  }

  func testCountsGrowWithMinutesAndStayDeterministic() {
    let early = stats(elapsed: 20)
    let late = stats(elapsed: 80)
    XCTAssertEqual(late, stats(elapsed: 80))
    XCTAssertLessThanOrEqual(early[11]?.passes ?? 0, late[11]?.passes ?? 0)
    XCTAssertLessThanOrEqual(late[11]?.accuratePasses ?? 0, late[11]?.passes ?? 0)
    XCTAssertLessThanOrEqual(late[11]?.duelsWon ?? 0, late[11]?.duels ?? 0)
    XCTAssertLessThanOrEqual(late[11]?.dribblesWon ?? 0, late[11]?.dribbles ?? 0)
    XCTAssertNotNil(late[11]?.rating)
  }

  func testNothingBeforeKickoffOrWithoutAnId() {
    XCTAssertTrue(stats(elapsed: 0).isEmpty)
    XCTAssertEqual(stats(elapsed: 90).count, 5, "the player without an id is skipped")
  }

  func testMockFeedServesScriptedStatsForTheMainMatchOnly() async throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "mock-match-script", withExtension: "json"))
    let script = try MatchScript.load(from: try Data(contentsOf: url))
    let base = Date(timeIntervalSince1970: 1_000_000)
    final class Clock: @unchecked Sendable { var date: Date; init(_ d: Date) { date = d } }
    let clock = Clock(base)
    let feed = MockFeed(script: script, now: { clock.date })
    let before = try await feed.playerStats(fixtureId: script.fixture.id)
    XCTAssertTrue(before.isEmpty)
    feed.start()
    clock.date = base.addingTimeInterval(5400)   // full time, 3-2
    let s = try await feed.playerStats(fixtureId: script.fixture.id)
    XCTAssertEqual(s[1460]?.goals, 1)      // B. Saka 18'
    XCTAssertEqual(s[19586]?.goals, 1)     // E. Eze 89'
    XCTAssertEqual(s[19586]?.assists, 1)   // for Saka
    XCTAssertEqual(s[37127]?.minutes, 63)  // M. Ødegaard off
    XCTAssertEqual(s[19465]?.conceded, 2)  // David Raya
    let other = try await feed.playerStats(fixtureId: script.other.id)
    XCTAssertTrue(other.isEmpty)
  }
}
