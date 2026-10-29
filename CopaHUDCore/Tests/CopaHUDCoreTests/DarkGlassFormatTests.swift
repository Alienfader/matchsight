import XCTest
@testable import CopaHUDCore

/// Dark glass: the Live page's latest events and the player page's four key
/// figures, chosen by position with the zeros left out.
final class DarkGlassFormatTests: XCTestCase {
  let flu = Team(id: 124, name: "Fluminense")
  let int = Team(id: 119, name: "Internacional")

  private func event(_ minute: Int, _ kind: MatchEvent.Kind, _ player: String, _ team: Team,
                     extra: Int? = nil) -> MatchEvent {
    MatchEvent(id: "\(minute)\(player)", fixtureId: 1, minute: minute, extraMinute: extra, team: team,
               player: player, assist: nil, kind: kind)
  }

  // MARK: latest events

  func testLatestIsNewestFirstWithoutSubstitutions() {
    let events = [event(46, .goal(.normal), "Alan Patrick", int),
                  event(58, .substitution, "Hulk", flu),
                  event(63, .card(.yellow), "Ignácio", flu),
                  event(70, .card(.yellow), "Renê", flu),
                  event(90, .goal(.normal), "Paulo Henrique Chagas de Lima", flu, extra: 3)]
    let latest = DarkGlassFormat.latest(events, limit: 3)
    XCTAssertEqual(latest.map(\.minute), ["90+3'", "70'", "63'"])
    XCTAssertEqual(latest.map(\.kind), [.goal, .yellow, .yellow])
    XCTAssertEqual(latest.map(\.team), ["FLU", "FLU", "FLU"])
    // Long names shorten to the surname; short ones stay whole.
    XCTAssertEqual(latest[0].name, "Lima")
    XCTAssertEqual(DarkGlassFormat.latest(events, limit: 5).last?.name, "Alan Patrick")
  }

  func testTheLineupNameWinsWhenThePlayerIsKnown() {
    // The feed's events carry full names; the lineup has the name he's known by.
    let events = [MatchEvent(id: "a", fixtureId: 1, minute: 70, extraMinute: nil, team: flu,
                             player: "Renê Rodrigues Martins", playerId: 9, assist: nil, kind: .card(.yellow))]
    let lineups = [Lineup(fixtureId: 1, team: flu, formation: "4-2-3-1", startXI: [
      LineupPlayer(name: "Renê", number: 6, position: "D", grid: "2:1", playerId: 9)], coach: nil)]
    XCTAssertEqual(DarkGlassFormat.latest(events, lineups: lineups).first?.name, "Renê")
    XCTAssertEqual(DarkGlassFormat.latest(events).first?.name, "Martins")
  }

  func testLatestKinds() {
    let events = [event(10, .goal(.ownGoal), "A", flu), event(20, .goal(.penalty), "B", flu),
                  event(30, .goal(.missedPenalty), "C", flu), event(40, .card(.red), "D", int),
                  event(50, .varDecision(detail: "Goal cancelled"), "E", int)]
    XCTAssertEqual(DarkGlassFormat.latest(events, limit: 9).map(\.kind),
                   [.varCheck, .red, .missedPenalty, .penalty, .ownGoal])
  }

  // MARK: key figures

  private func stats(passes: Int? = nil, accurate: Int? = nil, shots: Int? = nil, onTarget: Int? = nil,
                     tackles: Int? = nil, interceptions: Int? = nil, saves: Int? = nil,
                     conceded: Int? = nil, keyPasses: Int? = nil, duels: Int? = nil,
                     duelsWon: Int? = nil, dribbles: Int? = nil, dribblesWon: Int? = nil,
                     goals: Int? = nil, assists: Int? = nil) -> PlayerStats {
    PlayerStats(playerId: 1, passes: passes, shots: shots, tackles: tackles, interceptions: interceptions,
                goals: goals, assists: assists, saves: saves, conceded: conceded,
                shotsOnTarget: onTarget, keyPasses: keyPasses, accuratePasses: accurate,
                duels: duels, duelsWon: duelsWon, dribbles: dribbles, dribblesWon: dribblesWon)
  }

  func testADefenderShowsPassingAndDefendingWithoutZeros() {
    // Thiago Silva at 71': 76 passes (73 accurate), 0 tackles, 2 interceptions, 1 of 4 duels.
    let tiles = DarkGlassFormat.keyFigures(position: "D", stats: stats(
      passes: 76, accurate: 73, shots: 0, onTarget: 0, tackles: 0, interceptions: 2,
      keyPasses: 1, duels: 4, duelsWon: 1))
    XCTAssertEqual(tiles, [StatTile(value: "76", label: "PASSES · 96%"),
                           StatTile(value: "2", label: "INTERCEPTIONS"),
                           StatTile(value: "1/4", label: "DUELS WON"),
                           StatTile(value: "1", label: "KEY PASSES")])
  }

  func testAKeeperAlwaysShowsConceded() {
    let tiles = DarkGlassFormat.keyFigures(position: "G", stats: stats(
      passes: 12, accurate: 10, saves: 1, conceded: 0, duels: 0, duelsWon: 0))
    XCTAssertEqual(tiles, [StatTile(value: "1", label: "SAVES"),
                           StatTile(value: "0", label: "CONCEDED"),
                           StatTile(value: "12", label: "PASSES · 83%")])
  }

  func testGoalsAndAssistsLeadForAnyone() {
    let tiles = DarkGlassFormat.keyFigures(position: "D", stats: stats(
      passes: 40, tackles: 3, goals: 1, assists: 1))
    XCTAssertEqual(tiles.prefix(2).map(\.label), ["GOALS", "ASSISTS"])
    XCTAssertEqual(tiles.count, 4)
  }

  func testAForwardShowsShotsOnTarget() {
    let tiles = DarkGlassFormat.keyFigures(position: "F", stats: stats(
      passes: 14, accurate: 14, shots: 1, onTarget: 1, keyPasses: 2, dribbles: 0, dribblesWon: 0))
    XCTAssertEqual(tiles, [StatTile(value: "1", label: "SHOTS · 1 ON TARGET"),
                           StatTile(value: "2", label: "KEY PASSES"),
                           StatTile(value: "14", label: "PASSES · 100%")])
  }

  func testNoStatsNoTiles() {
    XCTAssertEqual(DarkGlassFormat.keyFigures(position: "M", stats: nil), [])
  }
}
