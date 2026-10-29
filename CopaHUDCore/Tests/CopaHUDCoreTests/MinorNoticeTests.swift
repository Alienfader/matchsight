import XCTest
@testable import CopaHUDCore

/// Yellow cards, substitutions and shots on target: a one-line toast on the
/// glasses, never the full-screen banner.
final class MinorNoticeTests: XCTestCase {
  let flu = Team(id: 124, name: "Fluminense")
  let int = Team(id: 119, name: "Internacional")
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  private func snap(_ h: Int, _ a: Int, min: Int) -> MatchSnapshot {
    MatchSnapshot(fixtureId: 1, home: flu, away: int, score: ScoreLine(home: h, away: a),
                  status: .secondHalf, elapsedMinutes: min, possessionHome: nil, groupLabel: nil,
                  kickoff: t0)
  }

  private func event(_ minute: Int, _ kind: MatchEvent.Kind, _ player: String, assist: String? = nil) -> MatchEvent {
    MatchEvent(id: "\(minute)-\(player)", fixtureId: 1, minute: minute, extraMinute: nil, team: flu,
               player: player, assist: assist, kind: kind)
  }

  // MARK: engine

  func testYellowCardsAndSubstitutionsBecomeMoments() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(0, 0, min: 1), events: [])
    // API-Football: `player` leaves, `assist` comes on (checked on recorded data).
    let out = engine.ingestFollowed(snapshot: snap(0, 0, min: 70), events: [
      event(58, .substitution, "Hulk", assist: "Lima"),
      event(70, .card(.yellow), "Renê Rodrigues Martins")])
    XCTAssertEqual(out.map(\.kind), [.substitution(playerIn: "Lima", playerOut: "Hulk", team: flu),
                                     .yellowCard(player: "Renê Rodrigues Martins", team: flu)])
  }

  func testFollowingMidMatchDoesNotReplayThem() {
    var engine = MatchEngine()
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(0, 0, min: 70),
                                         events: [event(63, .card(.yellow), "Ignácio")]), [])
  }

  // MARK: shots on target

  private func stats(home: Int?, away: Int?) -> MatchStats {
    MatchStats(home: TeamStats(shotsOnGoal: home), away: TeamStats(shotsOnGoal: away))
  }

  func testANewShotOnTargetIsANotice() {
    let out = StatsWatch.shotsOnTarget(previous: stats(home: 3, away: 1), current: stats(home: 4, away: 1),
                                       home: flu, away: int, minute: 72)
    XCTAssertEqual(out.map(\.kind), [.shotOnTarget(team: flu, total: 4)])
  }

  func testNoNoticeWithoutAnEarlierCountOrForAJump() {
    XCTAssertEqual(StatsWatch.shotsOnTarget(previous: nil, current: stats(home: 4, away: 1),
                                            home: flu, away: int, minute: 72), [])
    // A correction or a big catch-up after a gap isn't news.
    XCTAssertEqual(StatsWatch.shotsOnTarget(previous: stats(home: 4, away: 1), current: stats(home: 3, away: 6),
                                            home: flu, away: int, minute: 72), [])
  }

  // MARK: composer

  private func composer(_ config: HUDConfig = HUDConfig()) -> HUDComposer {
    var c = HUDComposer(config: config)
    c.update(followed: snap(0, 0, min: 70), events: [], lineups: [], others: [], isStale: false, now: t0)
    return c
  }

  func testNoticesAreToastsNotBanners() {
    var c = composer()
    c.enqueue([MatchMoment(fixtureId: 1, kind: .yellowCard(player: "Renê Rodrigues Martins", team: flu),
                           score: ScoreLine(home: 0, away: 0), minute: 70)], now: t0)
    let f = c.frame(now: t0)
    XCTAssertFalse(c.hasTakeover)
    XCTAssertEqual(f.toast, "🟨 Martins · FLU 70'")
  }

  func testNoticeLines() {
    XCTAssertEqual(HUDFormat.noticeLine(.substitution(playerIn: "Lima", playerOut: "Hulk", team: flu), minute: 58),
                   "🔁 Lima on for Hulk · FLU 58'")
    XCTAssertEqual(HUDFormat.noticeLine(.shotOnTarget(team: int, total: 2), minute: 72),
                   "🎯 Shot on target · INT (2)")
    XCTAssertNil(HUDFormat.noticeLine(.halfTime, minute: 45))
  }

  func testTheAppCanPostANotice() {
    // Lineups out before kickoff.
    var c = composer()
    c.notice("📋 Lineups are out", now: t0)
    XCTAssertEqual(c.frame(now: t0).toast, "📋 Lineups are out")
    c.tick(now: t0.addingTimeInterval(6))
    XCTAssertNil(c.frame(now: t0.addingTimeInterval(6)).toast)
    var quiet = composer(HUDConfig(minorNotices: false))
    quiet.notice("📋 Lineups are out", now: t0)
    XCTAssertNil(quiet.frame(now: t0).toast)
  }

  func testTheFullTimeRecapAsksForASummary() {
    XCTAssertTrue(InsightQuestion.fullTimeRecap.prompt.lowercased().contains("over"))
    XCTAssertFalse(InsightQuestion.presets.contains(.fullTimeRecap), "not a phone button")
  }

  func testNoticesCanBeTurnedOff() {
    var c = composer(HUDConfig(minorNotices: false))
    c.enqueue([MatchMoment(fixtureId: 1, kind: .shotOnTarget(team: flu, total: 4),
                           score: ScoreLine(home: 0, away: 0), minute: 72)], now: t0)
    XCTAssertNil(c.frame(now: t0).toast)
  }
}
