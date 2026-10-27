import XCTest
@testable import CopaHUDCore

/// MatchInsightContext is the ONLY match data the AI analyst sees: numbered
/// facts built from what the feed actually reported, plus a clock-free
/// fingerprint so unchanged data never triggers a new model call.
final class MatchInsightContextTests: XCTestCase {
  private let brazil = Team(id: 6, name: "Brazil")
  private let morocco = Team(id: 31, name: "Morocco")

  private func snapshot(elapsed: Int? = 67, status: MatchStatus = .secondHalf,
                        possessionHome: Int? = nil) -> MatchSnapshot {
    MatchSnapshot(fixtureId: 1489371, home: brazil, away: morocco,
                  score: ScoreLine(home: 2, away: 1), status: status,
                  elapsedMinutes: elapsed, possessionHome: possessionHome,
                  groupLabel: "Group Stage - 1", kickoff: Date(timeIntervalSince1970: 0))
  }

  private func event(_ minute: Int, _ kind: MatchEvent.Kind, team: Team? = nil,
                     player: String? = "Casemiro", assist: String? = nil) -> MatchEvent {
    MatchEvent(id: "e\(minute)-\(player ?? "nil")", fixtureId: 1489371, minute: minute,
               extraMinute: nil, team: team ?? brazil, player: player,
               assist: assist, kind: kind)
  }

  private func build(events: [MatchEvent] = [], lineups: [Lineup] = [],
                     stats: MatchStats? = nil, snap: MatchSnapshot? = nil) -> MatchInsightContext {
    MatchInsightContext.build(snapshot: snap ?? snapshot(), events: events, lineups: lineups,
                              stats: stats, isScripted: false)
  }

  private func texts(_ c: MatchInsightContext) -> [String] { c.facts.map(\.text) }

  func testScoreAndPhaseFactsFirst() {
    let c = build()
    XCTAssertEqual(c.facts[0], InsightFact(id: "F1", text: "Score: Brazil 2–1 Morocco"))
    XCTAssertEqual(c.facts[1].text, "Phase: 2nd half")
  }

  func testFormationFactsOnlyWhenLineupsPresent() {
    XCTAssertFalse(texts(build()).contains { $0.contains("formation") })
    let lineup = Lineup(fixtureId: 1489371, team: brazil, formation: "4-3-3",
                        startXI: [], coach: "Dorival Júnior")
    XCTAssertTrue(texts(build(lineups: [lineup]))
      .contains("Brazil formation: 4-3-3 (coach Dorival Júnior)"))
  }

  func testSubstitutionFactNamesOnAndOff() {
    let sub = event(61, .substitution, player: "Endrick", assist: "Rodrygo")
    XCTAssertTrue(texts(build(events: [sub])).contains("61' SUB Brazil: Rodrygo on, Endrick off"))
  }

  func testEventWithoutPlayerOmitsName() {
    let card = event(36, .card(.yellow), player: nil)
    XCTAssertTrue(texts(build(events: [card])).contains("36' YELLOW CARD Brazil"))
  }

  func testKeepsOnlyLatest12Events() {
    let cards = (1...40).reversed().map { event($0, .card(.yellow), player: "P\($0)") }
    let eventFacts = texts(build(events: cards)).filter { $0.contains("YELLOW CARD") }
    XCTAssertEqual(eventFacts.count, 12)
    XCTAssertEqual(eventFacts.first, "29' YELLOW CARD Brazil: P29")
    XCTAssertEqual(eventFacts.last, "40' YELLOW CARD Brazil: P40")
  }

  func testStatsRowsRequireBothSides() {
    let stats = MatchStats(home: TeamStats(totalShots: 9, expectedGoals: "1.84"),
                           away: TeamStats(totalShots: nil, expectedGoals: "0.62"))
    let t = texts(build(stats: stats))
    XCTAssertFalse(t.contains { $0.hasPrefix("Shots:") })
    XCTAssertTrue(t.contains("xG: Brazil 1.84 – Morocco 0.62"))
  }

  func testPossessionFallsBackToSnapshot() {
    let c = build(snap: snapshot(possessionHome: 61))
    XCTAssertTrue(texts(c).contains("Possession: Brazil 61% – Morocco 39%"))
  }

  func testFingerprintIgnoresClock() {
    let a = build(snap: snapshot(elapsed: 67))
    let b = build(snap: snapshot(elapsed: 70))
    XCTAssertEqual(a.fingerprint, b.fingerprint)
    XCTAssertNotEqual(a.headline, b.headline)
    let c = build(events: [event(68, .card(.yellow))], snap: snapshot(elapsed: 70))
    XCTAssertNotEqual(a.fingerprint, c.fingerprint)
  }

  func testIdsAreSequential() {
    let lineup = Lineup(fixtureId: 1489371, team: morocco, formation: "4-1-4-1",
                        startXI: [], coach: nil)
    let c = build(events: [event(18, .goal(.normal), player: "Raphinha")],
                  lineups: [lineup],
                  stats: MatchStats(home: TeamStats(corners: 3), away: TeamStats(corners: 1)))
    XCTAssertEqual(c.facts.map(\.id), (1...c.facts.count).map { "F\($0)" })
  }

  func testHeadlineIncludesGroupAndClock() {
    XCTAssertEqual(build().headline, "Brazil vs Morocco · Group Stage - 1 · 67'")
  }
}
