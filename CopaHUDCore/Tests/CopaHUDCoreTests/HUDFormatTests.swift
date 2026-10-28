import XCTest
@testable import CopaHUDCore

final class HUDFormatTests: XCTestCase {
  let bra = Team(id: 6, name: "Brazil")
  let arg = Team(id: 26, name: "Argentina")
  let fra = Team(id: 2, name: "France")
  let ger = Team(id: 25, name: "Germany")

  // MARK: possession bar

  func testPossessionBar65() {
    XCTAssertEqual(HUDFormat.possessionBar(home: 65), "▰▰▰▰▰▰▱▱▱▱")
  }

  func testPossessionBarEdges() {
    XCTAssertEqual(HUDFormat.possessionBar(home: 0), "▱▱▱▱▱▱▱▱▱▱")
    XCTAssertEqual(HUDFormat.possessionBar(home: 100), "▰▰▰▰▰▰▰▰▰▰")
    XCTAssertEqual(HUDFormat.possessionBar(home: 50), "▰▰▰▰▰▱▱▱▱▱")
    // out of range clamps, never crashes
    XCTAssertEqual(HUDFormat.possessionBar(home: -10).count, 10)
    XCTAssertEqual(HUDFormat.possessionBar(home: 150).count, 10)
  }

  // MARK: minute + kickoff

  func testMinuteLabel() {
    XCTAssertEqual(HUDFormat.minuteLabel(67, extra: nil), "67'")
    XCTAssertEqual(HUDFormat.minuteLabel(45, extra: 2), "45+2'")
    XCTAssertEqual(HUDFormat.minuteLabel(90, extra: 0), "90'")
  }

  func testKickoffTimeMatchesLocalFormatter() {
    let kickoff = Date(timeIntervalSince1970: 1_780_000_000)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = .current
    fmt.dateFormat = "HH:mm"
    XCTAssertEqual(HUDFormat.kickoffTime(kickoff), fmt.string(from: kickoff))
  }

  // MARK: score line

  func testScoreLine() {
    let s = HUDFormat.scoreLine(home: bra, away: arg, score: ScoreLine(home: 2, away: 1))
    XCTAssertEqual(s, "🇧🇷 BRA 2 · 1 ARG 🇦🇷")
  }

  // MARK: event lines

  func testEventLineGoal() {
    let e = MatchEvent(id: "g", fixtureId: 1, minute: 67, extraMinute: nil,
                       team: bra, player: "Neymar", assist: "Vinícius Júnior",
                       kind: .goal(.normal))
    XCTAssertEqual(HUDFormat.eventLine(e), "67' ⚽ Neymar (BRA)")
  }

  func testEventLineRedCard() {
    let e = MatchEvent(id: "r", fixtureId: 1, minute: 71, extraMinute: nil,
                       team: arg, player: "Otamendi", assist: nil, kind: .card(.red))
    XCTAssertEqual(HUDFormat.eventLine(e), "71' 🟥 Otamendi (ARG)")
  }

  func testEventLineVar() {
    let e = MatchEvent(id: "v", fixtureId: 1, minute: 73, extraMinute: nil,
                       team: bra, player: nil, assist: nil,
                       kind: .varDecision(detail: "Goal cancelled"))
    XCTAssertEqual(HUDFormat.eventLine(e), "73' VAR: Goal cancelled")
  }

  // MARK: other live + toast

  func testOtherLiveLine() {
    let snap = MatchSnapshot(fixtureId: 9, home: fra, away: ger,
                             score: ScoreLine(home: 2, away: 0), status: .secondHalf,
                             elapsedMinutes: 78, possessionHome: nil, groupLabel: nil,
                             kickoff: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(HUDFormat.otherLiveLine(snap), "FRA 2·0 GER · 78'")
  }

  func testToastLineWithScorer() {
    let snap = MatchSnapshot(fixtureId: 9, home: fra, away: ger,
                             score: ScoreLine(home: 2, away: 0), status: .secondHalf,
                             elapsedMinutes: 84, possessionHome: nil, groupLabel: nil,
                             kickoff: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(HUDFormat.toastLine(snapshot: snap, scorer: "Mbappé", minute: 84),
                   "⚽ FRA 2·0 GER · Mbappé 84'")
  }

  func testToastLineNoScorer() {
    let snap = MatchSnapshot(fixtureId: 9, home: fra, away: ger,
                             score: ScoreLine(home: 2, away: 0), status: .secondHalf,
                             elapsedMinutes: 84, possessionHome: nil, groupLabel: nil,
                             kickoff: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(HUDFormat.toastLine(snapshot: snap, scorer: nil, minute: nil),
                   "⚽ FRA 2·0 GER")
  }

  // MARK: lineup

  func testLineupTitleAndRows() {
    let xi = [
      LineupPlayer(name: "Alisson Becker", number: 1, position: "G", grid: "1:1"),
      LineupPlayer(name: "Danilo", number: 2, position: "D", grid: "2:1"),
      LineupPlayer(name: "Marquinhos", number: 4, position: "D", grid: "2:2"),
      LineupPlayer(name: "Casemiro", number: 5, position: "M", grid: "3:1"),
      LineupPlayer(name: "Neymar Jr", number: 10, position: "F", grid: "4:1"),
    ]
    let lineup = Lineup(fixtureId: 1, team: bra, formation: "4-2-3-1",
                        startXI: xi, coach: "Dorival")
    XCTAssertEqual(HUDFormat.lineupTitle(lineup), "🇧🇷 Brazil · 4-2-3-1")
    let rows = HUDFormat.lineupRows(lineup)
    XCTAssertEqual(rows, [
      "GK Becker",
      "DEF Danilo, Marquinhos",
      "MID Casemiro",
      "FWD Jr",
    ])
  }

  func testClubLineupHeaderHasFormationAndNoFlag() {
    let lineup = Lineup(fixtureId: 1, team: Team(id: 42, name: "Arsenal"), formation: "4-3-3",
                        startXI: [], coach: nil)
    XCTAssertEqual(HUDFormat.lineupTitle(lineup), "Arsenal · 4-3-3")
  }

  func testClubScoreLineHasNoStraySpaces() {
    XCTAssertEqual(HUDFormat.scoreLine(home: Team(id: 42, name: "Arsenal"), away: Team(id: 49, name: "Chelsea"),
                                       score: ScoreLine(home: 2, away: 1)),
                   "ARS 2 · 1 CHE")
  }

  func testLineupTitleNoFormation() {
    let lineup = Lineup(fixtureId: 1, team: bra, formation: nil, startXI: [], coach: nil)
    XCTAssertEqual(HUDFormat.lineupTitle(lineup), "🇧🇷 Brazil")
  }

  // MARK: players index (STARTING XI carousel)

  func testPlayerCardContent() {
    let xi = [
      LineupPlayer(name: "Alisson Becker", number: 1, position: "G", grid: "1:1", playerId: 280),
      LineupPlayer(name: "Vinícius Júnior", number: 7, position: "F", grid: "4:1", playerId: 762),
    ]
    let lineup = Lineup(fixtureId: 1, team: bra, formation: "4-2-3-1",
                        startXI: xi, coach: "Dorival")
    let card = HUDFormat.playerCard(lineup: lineup, cardIndex: 1)
    XCTAssertEqual(card.teamLine, "🇧🇷 Brazil · 4-2-3-1")  // position no longer embedded
    XCTAssertEqual(card.firstName, "Vinícius")
    XCTAssertEqual(card.lastName, "Júnior")
    XCTAssertEqual(card.number, "7")
    XCTAssertEqual(card.positionLabel, "FWD")
    XCTAssertEqual(card.photoURL, "https://media.api-sports.io/football/players/762.png")
    XCTAssertEqual(card.dots, "○●")
    XCTAssertEqual(card.counter, "2/2")
  }

  func testDotsAreCompact() {
    XCTAssertEqual(HUDFormat.dots(index: 0, count: 3), "●○○")
    XCTAssertEqual(HUDFormat.dots(index: 2, count: 11), "○○●○○○○○○○○")
  }

  func testRosterIndexCard() {
    let xi = [
      LineupPlayer(name: "Alisson Becker", number: 1, position: "G", grid: "1:1"),
      LineupPlayer(name: "Danilo", number: 2, position: "D", grid: "2:1"),
    ]
    let lineup = Lineup(fixtureId: 1, team: bra, formation: "4-2-3-1",
                        startXI: xi, coach: "Dorival")
    let index = HUDFormat.rosterIndex(lineup)
    XCTAssertEqual(index.title, "🇧🇷 Brazil · 4-2-3-1")
    XCTAssertEqual(index.rows, ["GK Becker", "DEF Danilo"])
    XCTAssertEqual(index.coachLine, "COACH Dorival")
    XCTAssertEqual(index.footer, "2 players · pinch ›")
  }

  func testRosterIndexCardNoCoach() {
    let lineup = Lineup(fixtureId: 1, team: bra, formation: nil,
                        startXI: [LineupPlayer(name: "Danilo", number: 2, position: "D", grid: nil)],
                        coach: nil)
    XCTAssertNil(HUDFormat.rosterIndex(lineup).coachLine)
  }

  // MARK: takeover content

  func testTakeoverGoal() {
    let m = MatchMoment(fixtureId: 1,
                        kind: .goal(scorer: "Neymar", assist: "Vinícius Júnior", detail: .normal),
                        score: ScoreLine(home: 2, away: 1), minute: 67)
    let t = HUDFormat.takeover(moment: m, home: bra, away: arg)
    XCTAssertEqual(t.headline, "GOOOAAALL! ⚽")
    XCTAssertEqual(t.scoreLine, "🇧🇷 BRA 2 · 1 ARG 🇦🇷")
    XCTAssertEqual(t.detail, "Neymar 67' · assist Vinícius Júnior")
  }

  func testTakeoverOwnGoalAndPenalty() {
    let og = MatchMoment(fixtureId: 1, kind: .goal(scorer: "Otamendi", assist: nil, detail: .ownGoal),
                         score: ScoreLine(home: 1, away: 0), minute: 30)
    XCTAssertEqual(HUDFormat.takeover(moment: og, home: bra, away: arg).headline, "OWN GOAL ⚽")
    XCTAssertEqual(HUDFormat.takeover(moment: og, home: bra, away: arg).detail, "Otamendi 30'")

    let pen = MatchMoment(fixtureId: 1, kind: .goal(scorer: "Neymar", assist: nil, detail: .penalty),
                          score: ScoreLine(home: 1, away: 0), minute: 30)
    XCTAssertEqual(HUDFormat.takeover(moment: pen, home: bra, away: arg).headline, "PENALTY GOAL ⚽")
  }

  func testTakeoverRedCard() {
    let m = MatchMoment(fixtureId: 1, kind: .redCard(player: "Otamendi", team: arg),
                        score: ScoreLine(home: 2, away: 1), minute: 71)
    let t = HUDFormat.takeover(moment: m, home: bra, away: arg)
    XCTAssertEqual(t.headline, "🟥 SENT OFF")
    XCTAssertEqual(t.detail, "Otamendi 71'")
  }

  func testTakeoverPenaltyAwarded() {
    let m = MatchMoment(fixtureId: 1, kind: .penaltyAwarded(team: bra),
                        score: ScoreLine(home: 1, away: 1), minute: 55)
    XCTAssertEqual(HUDFormat.takeover(moment: m, home: bra, away: arg).headline, "PEN to BRA")
  }

  func testTakeoverVarDecisions() {
    func head(_ o: VarOutcome) -> String {
      HUDFormat.takeover(moment: MatchMoment(fixtureId: 1, kind: .varDecision(o),
                                             score: ScoreLine(home: 1, away: 1), minute: 60),
                         home: bra, away: arg).headline
    }
    XCTAssertEqual(head(.goalOverturned), "VAR: GOAL OVERTURNED")
    XCTAssertEqual(head(.goalStands), "VAR: GOAL STANDS")
    XCTAssertEqual(head(.goalAwarded), "VAR: GOAL AWARDED")
    XCTAssertEqual(head(.penaltyCancelled), "VAR: PEN CANCELLED")
  }

  func testTakeoverHalfFullTime() {
    let ht = MatchMoment(fixtureId: 1, kind: .halfTime, score: ScoreLine(home: 1, away: 0), minute: 45)
    XCTAssertEqual(HUDFormat.takeover(moment: ht, home: bra, away: arg).headline, "HALF-TIME")
    let ft = MatchMoment(fixtureId: 1, kind: .fullTime, score: ScoreLine(home: 2, away: 1), minute: 90)
    XCTAssertEqual(HUDFormat.takeover(moment: ft, home: bra, away: arg).headline, "FULL-TIME")
    XCTAssertEqual(HUDFormat.takeover(moment: ft, home: bra, away: arg).scoreLine,
                   "🇧🇷 BRA 2 · 1 ARG 🇦🇷")
  }

  // MARK: player detail (pinch on a player card)

  private func detailStats(minutes: Int? = 52, rating: String? = "7.2",
                           yellow: Int = 0, red: Int = 0) -> PlayerStats {
    PlayerStats(playerId: 1146, passes: 24, shots: 1, tackles: 2, interceptions: 2,
                minutes: minutes, rating: rating, goals: 1, assists: 0, saves: 0, conceded: 0,
                shotsOnTarget: 1, keyPasses: 2, accuratePasses: 20, duels: 4, duelsWon: 3,
                dribbles: 1, dribblesWon: 1, foulsDrawn: 0, foulsCommitted: 1,
                yellowCards: yellow, redCards: red)
  }

  func testPlayerDetailOutfieldRows() {
    let rows = HUDFormat.playerDetailRows(detailStats(), position: "D")
    XCTAssertEqual(rows, [
      PlayerStatRow(label: "Goals", value: "1"),
      PlayerStatRow(label: "Assists", value: "0"),
      PlayerStatRow(label: "Shots", value: "1 (1 on target)"),
      PlayerStatRow(label: "Key passes", value: "2"),
      PlayerStatRow(label: "Passes", value: "24 (20 accurate)"),
      PlayerStatRow(label: "Tackles", value: "2"),
      PlayerStatRow(label: "Interceptions", value: "2"),
      PlayerStatRow(label: "Duels won", value: "3 of 4"),
      PlayerStatRow(label: "Dribbles", value: "1 of 1"),
      PlayerStatRow(label: "Fouls", value: "1"),
    ])
  }

  func testPlayerDetailKeeperRows() {
    let rows = HUDFormat.playerDetailRows(detailStats(), position: "G")
    XCTAssertEqual(rows.map(\.label), ["Saves", "Conceded", "Passes", "Duels won", "Fouls"])
  }

  func testPlayerDetailCardsOnlyWhenShown() {
    XCTAssertFalse(HUDFormat.playerDetailRows(detailStats(), position: "M").contains { $0.label == "Cards" })
    XCTAssertEqual(HUDFormat.playerDetailRows(detailStats(yellow: 1), position: "M").last,
                   PlayerStatRow(label: "Cards", value: "1 yellow"))
    XCTAssertEqual(HUDFormat.playerDetailRows(detailStats(yellow: 1, red: 1), position: "M").last,
                   PlayerStatRow(label: "Cards", value: "1 yellow · 1 red"))
  }

  func testPlayerDetailMissingFieldsAreLeftOff() {
    let s = PlayerStats(playerId: 1, passes: 10, shots: nil, tackles: nil, interceptions: nil,
                        minutes: 30, accuratePasses: nil)
    XCTAssertEqual(HUDFormat.playerDetailRows(s, position: "F"),
                   [PlayerStatRow(label: "Passes", value: "10")])
  }

  func testPlayerDetailNoStatsWithoutMinutes() {
    XCTAssertEqual(HUDFormat.playerDetailRows(nil, position: "F"), [])
    XCTAssertEqual(HUDFormat.playerDetailRows(detailStats(minutes: nil), position: "F"), [])
    XCTAssertNil(HUDFormat.playerSummary(nil))
    XCTAssertNil(HUDFormat.playerSummary(detailStats(minutes: 0)))
  }

  func testPlayerSummary() {
    XCTAssertEqual(HUDFormat.playerSummary(detailStats()), "Rating 7.2 · 52 min")
    XCTAssertEqual(HUDFormat.playerSummary(detailStats(rating: nil)), "52 min")
  }
}
