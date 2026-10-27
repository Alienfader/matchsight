import XCTest
@testable import CopaHUDCore

final class HUDComposerTests: XCTestCase {
  let bra = Team(id: 6, name: "Brazil")
  let arg = Team(id: 26, name: "Argentina")
  let fra = Team(id: 2, name: "France")
  let ger = Team(id: 25, name: "Germany")
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  func snapshot(score: ScoreLine = ScoreLine(home: 1, away: 0),
                status: MatchStatus = .firstHalf,
                elapsed: Int? = 30,
                possession: Int? = nil) -> MatchSnapshot {
    MatchSnapshot(fixtureId: 1, home: bra, away: arg, score: score, status: status,
                  elapsedMinutes: elapsed, possessionHome: possession,
                  groupLabel: "Group C", kickoff: t0)
  }

  func goalMoment(score: ScoreLine = ScoreLine(home: 2, away: 0)) -> MatchMoment {
    MatchMoment(fixtureId: 1, kind: .goal(scorer: "Neymar", assist: nil, detail: .normal),
                score: score, minute: 67)
  }

  func otherGoal() -> MatchMoment {
    let snap = MatchSnapshot(fixtureId: 9, home: fra, away: ger, score: ScoreLine(home: 2, away: 0),
                             status: .secondHalf, elapsedMinutes: 84, possessionHome: nil,
                             groupLabel: nil, kickoff: t0)
    return MatchMoment(fixtureId: 9, kind: .otherMatchGoal(snapshot: snap, scorer: "Mbappé"),
                       score: ScoreLine(home: 2, away: 0), minute: 84)
  }

  func loaded(config: HUDConfig = HUDConfig()) -> HUDComposer {
    var c = HUDComposer(config: config)
    let events = [
      MatchEvent(id: "e1", fixtureId: 1, minute: 12, extraMinute: nil, team: bra,
                 player: "Raphinha", assist: nil, kind: .goal(.normal)),
    ]
    let lineups = [
      Lineup(fixtureId: 1, team: bra, formation: "4-2-3-1", startXI: [
        LineupPlayer(name: "Alisson Becker", number: 1, position: "G", grid: "1:1"),
      ], coach: "Dorival"),
      Lineup(fixtureId: 1, team: arg, formation: "4-4-2", startXI: [
        LineupPlayer(name: "Emiliano Martínez", number: 23, position: "G", grid: "1:1"),
      ], coach: "Scaloni"),
    ]
    let others = [
      MatchSnapshot(fixtureId: 9, home: fra, away: ger, score: ScoreLine(home: 2, away: 0),
                    status: .secondHalf, elapsedMinutes: 78, possessionHome: nil,
                    groupLabel: nil, kickoff: t0),
    ]
    c.update(followed: snapshot(), events: events, lineups: lineups, others: others,
             isStale: false, now: t0)
    return c
  }

  // MARK: deck

  func testDeckWrapsForwardThroughSevenPages() {
    var c = loaded()
    func bodyName() -> String {
      switch c.frame(now: t0).body {
      case .panel: return "panel"
      case .events: return "events"
      case .lineup: return "lineup"
      case .playerCard: return "playerCard"
      case .stats: return "stats"
      case .otherLive: return "otherLive"
      case .takeover: return "takeover"
      case .intro: return "intro"
      case .insight: return "insight"
      case .message: return "message"
      }
    }
    XCTAssertEqual(bodyName(), "panel")
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "message")   // insight page, warming
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "events")
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "lineup")     // home index card
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "playerCard") // home XI (1 player)
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "lineup")     // away index card
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "playerCard") // away XI (1 player)
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "stats")
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "otherLive")
    c.handleTapBurst(count: 1, now: t0); XCTAssertEqual(bodyName(), "panel") // wrap
  }

  func testStatsPageRendersBarsAndHonestEmpty() {
    var c = loaded()
    // insight → events → home index → home card → away index → away card → stats
    for _ in 1...7 { c.handleTapBurst(count: 1, now: t0) }
    guard case let .stats(title, emptyLines) = c.frame(now: t0).body else {
      return XCTFail("stats page")
    }
    XCTAssertEqual(title, "BRA · stats · ARG")
    XCTAssertEqual(emptyLines, ["no stats yet"])  // no stats supplied yet

    let stats = MatchStats(
      home: TeamStats(possession: 60, totalShots: 12, shotsOnGoal: 5,
                      corners: 7, yellowCards: 1, redCards: 0, expectedGoals: "1.84"),
      away: TeamStats(possession: 40, totalShots: 8, shotsOnGoal: 3,
                      corners: 2, yellowCards: 3, redCards: 1, expectedGoals: "0.92"))
    c.update(followed: snapshot(), events: [], lineups: [], others: [],
             stats: stats, isStale: false, now: t0)
    guard case let .stats(_, lines) = c.frame(now: t0).body else {
      return XCTFail("stats page after update")
    }
    XCTAssertEqual(lines[0], "POSS  ▰▰▰▰▰▰▱▱▱▱  60%")
    XCTAssertTrue(lines.contains("SHOTS  12 · 8"))
    XCTAssertTrue(lines.contains("xG  1.84 · 0.92"))
  }

  func testGoalTakeoverCarriesScorerHeadshot() {
    var c = loaded()
    let goal = MatchMoment(fixtureId: 1,
                           kind: .goal(scorer: "Neymar", assist: nil, detail: .normal),
                           score: ScoreLine(home: 1, away: 0), minute: 30, playerId: 276)
    c.enqueue([goal], now: t0)
    guard case let .takeover(content) = c.frame(now: t0).body else {
      return XCTFail("takeover")
    }
    XCTAssertEqual(content.imageURL, "https://media.api-sports.io/football/players/276.png")
  }

  func testCurrentXITeamFollowsTheLineupPage() {
    var c = loaded()
    XCTAssertNil(c.currentXITeam, "not on a lineup page")
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    c.handleTapBurst(count: 1, now: t0) // lineup home
    XCTAssertEqual(c.currentXITeam?.id, bra.id)
  }

  func testLineupPagesAreHomeIndexThenCardsThenAway() {
    var c = loaded()
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    c.handleTapBurst(count: 1, now: t0) // lineup home → index card first
    guard case let .lineup(homeIndex) = c.frame(now: t0).body else { return XCTFail("home index") }
    XCTAssertTrue(homeIndex.title.contains("Brazil"))
    XCTAssertEqual(homeIndex.rows, ["GK Becker"])
    XCTAssertEqual(homeIndex.coachLine, "COACH Dorival")
    XCTAssertEqual(homeIndex.footer, "1 player · pinch ›")
    c.handleTapBurst(count: 1, now: t0) // home player card
    guard case let .playerCard(home) = c.frame(now: t0).body else { return XCTFail("home card") }
    XCTAssertTrue(home.teamLine.contains("Brazil"))
    XCTAssertEqual(home.firstName, "Alisson")
    XCTAssertEqual(home.lastName, "Becker")
    XCTAssertEqual(home.number, "1")
    XCTAssertEqual(home.positionLabel, "GK")
    XCTAssertEqual(home.counter, "1/1")
    c.handleTapBurst(count: 1, now: t0) // lineup away → index card
    guard case let .lineup(awayIndex) = c.frame(now: t0).body else { return XCTFail("away index") }
    XCTAssertTrue(awayIndex.title.contains("Argentina"))
    c.handleTapBurst(count: 1, now: t0) // away player card
    guard case let .playerCard(away) = c.frame(now: t0).body else { return XCTFail("away card") }
    XCTAssertTrue(away.teamLine.contains("Argentina"))
    XCTAssertEqual(away.lastName, "Martínez")
  }

  func testLineupCarouselAdvancesPerTapThenFlowsToNextPage() {
    var c = HUDComposer()
    let xi = (1...11).map { n in
      LineupPlayer(name: "Player \(n)", number: n, position: "M", grid: nil, playerId: 100 + n)
    }
    c.update(followed: snapshot(),
             events: [], lineups: [Lineup(fixtureId: 1, team: bra, formation: "4-3-3",
                                          startXI: xi, coach: nil)],
             others: [], isStale: false, now: t0)
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    c.handleTapBurst(count: 1, now: t0) // lineup home → roster index card
    guard case let .lineup(index) = c.frame(now: t0).body else { return XCTFail("index card") }
    XCTAssertEqual(index.footer, "11 players · pinch ›")
    c.handleTapBurst(count: 1, now: t0) // card 1
    guard case let .playerCard(first) = c.frame(now: t0).body else { return XCTFail("card 1") }
    XCTAssertEqual(first.lastName, "1")
    XCTAssertEqual(first.photoURL, "https://media.api-sports.io/football/players/101.png")
    XCTAssertTrue(first.dots.hasPrefix("●"))
    XCTAssertEqual(first.counter, "1/11")
    for n in 2...11 {                       // tap through the rest of the XI
      c.handleTapBurst(count: 1, now: t0)
      guard case let .playerCard(card) = c.frame(now: t0).body else { return XCTFail("card \(n)") }
      XCTAssertEqual(card.lastName, "\(n)")
      XCTAssertEqual(card.counter, "\(n)/11")
    }
    c.handleTapBurst(count: 1, now: t0)     // past the last card → away lineup (no data) → text page
    guard case let .lineup(fallback) = c.frame(now: t0).body else { return XCTFail("flows to next page") }
    XCTAssertEqual(fallback.rows, ["lineup not available"])
    XCTAssertNil(fallback.footer)           // no carousel behind the fallback page
    c.handleTapBurst(count: 2, now: t0)     // 2-tap home resets the carousel
    guard case .panel = c.frame(now: t0).body else { return XCTFail("home") }
  }

  func testDoublePinchStepsBackThroughLineupThenHome() {
    var c = HUDComposer()
    let xi = (1...11).map { n in
      LineupPlayer(name: "Player \(n)", number: n, position: "M", grid: nil, playerId: 100 + n)
    }
    c.update(followed: snapshot(),
             events: [], lineups: [Lineup(fixtureId: 1, team: bra, formation: "4-3-3",
                                          startXI: xi, coach: nil)],
             others: [], isStale: false, now: t0)
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    c.handleTapBurst(count: 1, now: t0) // lineup home → roster index card
    for _ in 1...4 { c.handleTapBurst(count: 1, now: t0) }   // forward to card 4
    guard case let .playerCard(card4) = c.frame(now: t0).body else { return XCTFail("card 4") }
    XCTAssertEqual(card4.lastName, "4")

    c.handleTapBurst(count: 2, now: t0)   // double-pinch steps BACK to card 3
    guard case let .playerCard(card3) = c.frame(now: t0).body else { return XCTFail("back to 3") }
    XCTAssertEqual(card3.lastName, "3")

    c.handleTapBurst(count: 2, now: t0)   // back to 2
    c.handleTapBurst(count: 2, now: t0)   // back to 1 (first card)
    guard case let .playerCard(card1) = c.frame(now: t0).body else { return XCTFail("back to 1") }
    XCTAssertEqual(card1.lastName, "1")

    c.handleTapBurst(count: 2, now: t0)   // back past card 1 → roster index card
    guard case .lineup = c.frame(now: t0).body else { return XCTFail("back to index card") }

    c.handleTapBurst(count: 2, now: t0)   // at the index card, double-pinch falls through to home
    guard case .panel = c.frame(now: t0).body else { return XCTFail("home from index card") }
  }

  func testEmptyDeckPagesRenderHonestly() {
    var c = HUDComposer()
    c.update(followed: snapshot(), events: [], lineups: [], others: [], isStale: false, now: t0)
    c.handleTapBurst(count: 1, now: t0) // insight
    guard case .message("AI Analyst warming up…") = c.frame(now: t0).body else { return XCTFail() }
    c.handleTapBurst(count: 1, now: t0)
    guard case let .events(_, lines) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(lines, ["no events yet"])
    c.handleTapBurst(count: 1, now: t0)
    guard case let .lineup(home) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(home.rows, ["lineup not available"])
    c.handleTapBurst(count: 1, now: t0) // away
    c.handleTapBurst(count: 1, now: t0) // stats
    guard case let .stats(_, sLines) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(sLines, ["no stats yet"])
    c.handleTapBurst(count: 1, now: t0) // other live
    guard case let .otherLive(_, oLines) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(oLines, ["no other matches live"])
  }

  func testTwoTapJumpsHomeFromNonCarouselPages() {
    var c = loaded()
    // From the events page: 2-tap means jump home.
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 2, now: t0)
    guard case .panel = c.frame(now: t0).body else { return XCTFail("expected panel from events") }
    // From a roster index card (carousel at its front) it also falls through home.
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 1, now: t0) // home lineup → roster index card
    c.handleTapBurst(count: 2, now: t0)
    guard case .panel = c.frame(now: t0).body else { return XCTFail("expected panel from index card") }
  }

  // MARK: AI insight page

  func testInsightPageIsOnePinchFromPanel() {
    var c = loaded()
    c.setInsight(InsightContent(title: "T", body: "B", footer: "F"))
    c.handleTapBurst(count: 1, now: t0)
    XCTAssertTrue(c.isOnInsightPage)
    XCTAssertEqual(c.frame(now: t0).body, .insight(InsightContent(title: "T", body: "B", footer: "F")))
  }

  func testInsightPageWarmingWhenNil() {
    var c = loaded()
    c.handleTapBurst(count: 1, now: t0)
    XCTAssertEqual(c.frame(now: t0).body, .message("AI Analyst warming up…"))
  }

  func testInsightPageWithoutFollowedMatch() {
    var c = HUDComposer()
    c.setInsight(InsightContent(title: "T", body: "B", footer: "F"))
    c.showInsightPage()
    XCTAssertEqual(c.frame(now: t0).body, .message("No match followed"))
  }

  func testShowInsightPageJumpsFromAnyPage() {
    var c = loaded()
    for _ in 1...3 { c.handleTapBurst(count: 1, now: t0) }   // home lineup index card
    c.showInsightPage()
    XCTAssertTrue(c.isOnInsightPage)
    XCTAssertEqual(c.frame(now: t0).body, .message("AI Analyst warming up…"))
    c.handleTapBurst(count: 1, now: t0)                      // carousel reset: next is events
    guard case .events = c.frame(now: t0).body else { return XCTFail("events after insight") }
  }

  func testSetInsightDoesNotMovePage() {
    var c = loaded()
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 1, now: t0) // events
    c.setInsight(InsightContent(title: "T", body: "B", footer: "F"))
    guard case .events = c.frame(now: t0).body else { return XCTFail("still events") }
    XCTAssertFalse(c.isOnInsightPage)
  }

  func testInsightSurvivesUpdate() {
    var c = loaded()
    c.setInsight(InsightContent(title: "T", body: "B", footer: "F"))
    c.showInsightPage()
    c.update(followed: snapshot(), events: [], lineups: [], others: [], isStale: false, now: t0)
    XCTAssertEqual(c.frame(now: t0).body, .insight(InsightContent(title: "T", body: "B", footer: "F")))
  }

  func testTwoTapFromInsightGoesHome() {
    var c = loaded()
    c.handleTapBurst(count: 1, now: t0)
    c.handleTapBurst(count: 2, now: t0)
    guard case .panel = c.frame(now: t0).body else { return XCTFail("home") }
  }

  // MARK: pause

  func testThreeTapTogglesPauseAndPanelShowsBell() {
    var c = loaded()
    XCTAssertFalse(c.alertsPaused)
    c.handleTapBurst(count: 3, now: t0)
    XCTAssertTrue(c.alertsPaused)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertTrue(p.alertsPaused)
    c.handleTapBurst(count: 4, now: t0) // 3+ also toggles
    XCTAssertFalse(c.alertsPaused)
  }

  func testEnqueueDroppedWhilePaused() {
    var c = loaded()
    c.handleTapBurst(count: 3, now: t0) // pause
    c.enqueue([goalMoment(), otherGoal()], now: t0)
    let f = c.frame(now: t0)
    guard case .panel = f.body else { return XCTFail("takeover should have been dropped") }
    XCTAssertNil(f.toast)
  }

  // MARK: takeovers

  func testTakeoverPlaysThenReturnsToPriorPage() {
    var c = loaded()
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // move to events page first
    c.enqueue([goalMoment()], now: t0)
    guard case let .takeover(tk) = c.frame(now: t0).body else { return XCTFail("takeover") }
    XCTAssertEqual(tk.headline, "GOOOAAALL! ⚽")
    // still holding before deadline (default 8s)
    c.tick(now: t0.addingTimeInterval(7))
    guard case .takeover = c.frame(now: t0.addingTimeInterval(7)).body else { return XCTFail("still holding") }
    // after deadline -> back to the events page the user was on
    c.tick(now: t0.addingTimeInterval(9))
    guard case .events = c.frame(now: t0.addingTimeInterval(9)).body else { return XCTFail("return to events") }
  }

  func testTakeoversPlaySequentially() {
    var c = loaded()
    let g1 = MatchMoment(fixtureId: 1, kind: .goal(scorer: "A", assist: nil, detail: .normal),
                         score: ScoreLine(home: 1, away: 0), minute: 10)
    let g2 = MatchMoment(fixtureId: 1, kind: .redCard(player: "B", team: arg),
                         score: ScoreLine(home: 1, away: 0), minute: 20)
    c.enqueue([g1, g2], now: t0)
    guard case let .takeover(first) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(first.headline, "GOOOAAALL! ⚽")
    c.tick(now: t0.addingTimeInterval(9))
    guard case let .takeover(second) = c.frame(now: t0.addingTimeInterval(9)).body else { return XCTFail() }
    XCTAssertEqual(second.headline, "🟥 SENT OFF")
    c.tick(now: t0.addingTimeInterval(18))
    guard case .panel = c.frame(now: t0.addingTimeInterval(18)).body else { return XCTFail("drained") }
  }

  func testTwoTapDismissesTakeoverEarly() {
    var c = loaded()
    c.enqueue([goalMoment()], now: t0)
    guard case .takeover = c.frame(now: t0).body else { return XCTFail() }
    c.handleTapBurst(count: 2, now: t0)
    guard case .panel = c.frame(now: t0).body else { return XCTFail("dismissed to panel") }
  }

  func testTapDuringTakeoverActsOnDeckUnderneath() {
    var c = loaded() // page = panel
    c.enqueue([goalMoment()], now: t0)
    c.handleTapBurst(count: 1, now: t0) // advance underneath panel -> insight
    c.tick(now: t0.addingTimeInterval(9)) // takeover expires
    guard case .message("AI Analyst warming up…") = c.frame(now: t0.addingTimeInterval(9)).body else {
      return XCTFail("should reveal the advanced page")
    }
  }

  // MARK: toasts

  func testToastOverlayAndExpiry() {
    var c = loaded()
    c.enqueue([otherGoal()], now: t0)
    XCTAssertEqual(c.frame(now: t0).toast, "⚽ FRA 2·0 GER · Mbappé 84'")
    c.tick(now: t0.addingTimeInterval(4))
    XCTAssertNotNil(c.frame(now: t0.addingTimeInterval(4)).toast)
    c.tick(now: t0.addingTimeInterval(6)) // default 5s
    XCTAssertNil(c.frame(now: t0.addingTimeInterval(6)).toast)
  }

  func testToastsDisabledByConfig() {
    var c = loaded(config: HUDConfig(toastsEnabled: false))
    c.enqueue([otherGoal()], now: t0)
    XCTAssertNil(c.frame(now: t0).toast)
  }

  func testToastOverlaysTakeoverTail() {
    var c = loaded()
    c.enqueue([goalMoment(), otherGoal()], now: t0)
    let f = c.frame(now: t0)
    guard case .takeover = f.body else { return XCTFail("takeover body") }
    XCTAssertEqual(f.toast, "⚽ FRA 2·0 GER · Mbappé 84'")
  }

  func testOnlyNewestToastShows() {
    var c = loaded()
    c.enqueue([otherGoal()], now: t0)
    let snap = MatchSnapshot(fixtureId: 10, home: ger, away: fra, score: ScoreLine(home: 1, away: 1),
                             status: .secondHalf, elapsedMinutes: 90, possessionHome: nil,
                             groupLabel: nil, kickoff: t0)
    let newer = MatchMoment(fixtureId: 10, kind: .otherMatchGoal(snapshot: snap, scorer: "Wirtz"),
                            score: ScoreLine(home: 1, away: 1), minute: 90)
    c.enqueue([newer], now: t0.addingTimeInterval(1))
    XCTAssertEqual(c.frame(now: t0.addingTimeInterval(1)).toast, "⚽ GER 1·1 FRA · Wirtz 90'")
  }

  // MARK: clock interpolation

  func testClockInterpolatesBetweenUpdates() {
    var c = HUDComposer()
    c.update(followed: snapshot(status: .firstHalf, elapsed: 10), events: [], lineups: [],
             others: [], isStale: false, now: t0)
    guard case let .panel(p0) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(p0.clock, "10'")
    c.tick(now: t0.addingTimeInterval(65))
    guard case let .panel(p1) = c.frame(now: t0.addingTimeInterval(65)).body else { return XCTFail() }
    XCTAssertEqual(p1.clock, "11'")
  }

  func testClockNeverGoesBackward() {
    var c = HUDComposer()
    c.update(followed: snapshot(status: .firstHalf, elapsed: 67), events: [], lineups: [],
             others: [], isStale: false, now: t0)
    c.tick(now: t0)
    guard case let .panel(p0) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(p0.clock, "67'")
    // feed glitches to a lower minute
    c.update(followed: snapshot(status: .firstHalf, elapsed: 65), events: [], lineups: [],
             others: [], isStale: false, now: t0.addingTimeInterval(1))
    guard case let .panel(p1) = c.frame(now: t0.addingTimeInterval(1)).body else { return XCTFail() }
    XCTAssertEqual(p1.clock, "67'")
  }

  func testClockStatusFormats() {
    var c = HUDComposer()
    // not started -> kickoff time
    c.update(followed: snapshot(status: .notStarted, elapsed: nil), events: [], lineups: [],
             others: [], isStale: false, now: t0)
    guard case let .panel(ns) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(ns.clock, HUDFormat.kickoffTime(t0))
    // half time
    c.update(followed: snapshot(status: .halfTime, elapsed: 45), events: [], lineups: [],
             others: [], isStale: false, now: t0)
    guard case let .panel(ht) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(ht.clock, "HT")
    // full time
    c.update(followed: snapshot(status: .finished, elapsed: 90), events: [], lineups: [],
             others: [], isStale: false, now: t0)
    guard case let .panel(ft) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(ft.clock, "FT")
  }

  // MARK: panel content

  func testPanelCarriesClubCrests() throws {
    let logo = URL(string: "https://media.api-sports.io/football/teams/42.png")!
    var c = HUDComposer()
    let snap = MatchSnapshot(fixtureId: 7, home: Team(id: 42, name: "Arsenal", logoURL: logo),
                             away: Team(id: 49, name: "Chelsea"), score: ScoreLine(home: 1, away: 0),
                             status: .secondHalf, elapsedMinutes: 63, possessionHome: nil,
                             groupLabel: "Premier League", kickoff: t0)
    c.update(followed: snap, events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertEqual(p.homeCode, "ARS"); XCTAssertEqual(p.homeCrestURL, logo); XCTAssertEqual(p.homeFlag, "")
    XCTAssertEqual(p.awayCode, "CHE")
    XCTAssertEqual(p.scoreText, "ARS 1 · 0 CHE")
  }

  // MARK: - Crest intro (Task 9)

  func club(_ status: MatchStatus = .notStarted, id: Int = 77, score: ScoreLine = ScoreLine(home: 0, away: 0)) -> MatchSnapshot {
    MatchSnapshot(fixtureId: id,
                  home: Team(id: 42, name: "Arsenal", logoURL: URL(string: "https://media.api-sports.io/football/teams/42.png")),
                  away: Team(id: 49, name: "Chelsea", logoURL: URL(string: "https://media.api-sports.io/football/teams/49.png")),
                  score: score, status: status, elapsedMinutes: nil, possessionHome: nil,
                  groupLabel: "Premier League", kickoff: t0)
  }

  /// Poll update + the app's "new match followed" call.
  func feed(_ c: inout HUDComposer, _ s: MatchSnapshot?, at t: Date) {
    c.update(followed: s, events: [], lineups: [], others: [], isStale: false, now: t)
    c.showMatchIntro(now: t)
  }

  func testUpdateAloneNeverShowsIntro() {
    var c = HUDComposer()
    c.update(followed: club(), events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case .panel = c.frame(now: t0).body else { return XCTFail("intro only on showMatchIntro") }
  }

  func testIntroShownWhenFollowedFixtureChanges() {
    var c = HUDComposer()
    feed(&c, club(), at: t0)
    guard case let .intro(i) = c.frame(now: t0).body else { return XCTFail("expected intro") }
    XCTAssertEqual(i.homeCode, "ARS"); XCTAssertEqual(i.awayCode, "CHE")
    XCTAssertEqual(i.homeCrestURL?.absoluteString, "https://media.api-sports.io/football/teams/42.png")
    XCTAssertEqual(i.competition, "Premier League")
  }

  func testIntroPrefersCompetitionOverRoundLabel() {
    // Live API-Football snapshots carry the round ("Regular Season - 10") as
    // the group label; the intro names the league the app passes in.
    var c = HUDComposer()
    let s = club()
    let live = MatchSnapshot(fixtureId: s.fixtureId, home: s.home, away: s.away, score: s.score,
                             status: s.status, elapsedMinutes: nil, possessionHome: nil,
                             groupLabel: "Regular Season - 10", kickoff: t0)
    c.update(followed: live, events: [], lineups: [], others: [], isStale: false, now: t0)
    c.setCompetition("Premier League")
    c.showMatchIntro(now: t0)
    guard case let .intro(i) = c.frame(now: t0).body else { return XCTFail("expected intro") }
    XCTAssertEqual(i.competition, "Premier League")
  }

  func testPanelLabelPrefersCompetitionOverRoundLabel() {
    var c = HUDComposer()
    let s = club(.firstHalf)
    let live = MatchSnapshot(fixtureId: s.fixtureId, home: s.home, away: s.away, score: s.score,
                             status: s.status, elapsedMinutes: 10, possessionHome: nil,
                             groupLabel: "Regular Season - 10", kickoff: t0)
    c.update(followed: live, events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(before) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertEqual(before.groupLabel, "Regular Season - 10")
    c.setCompetition("Premier League")
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertEqual(p.groupLabel, "Premier League")
    c.showMatchIntro(now: t0)
    guard case let .intro(i) = c.frame(now: t0).body else { return XCTFail("expected intro") }
    XCTAssertEqual(i.competition, "Premier League")
  }

  // MARK: - Score panel timeline

  private func panelAt(minute: Int, events: [MatchEvent]) -> PanelContent? {
    var c = HUDComposer()
    let s = club(.secondHalf)
    let live = MatchSnapshot(fixtureId: s.fixtureId, home: s.home, away: s.away, score: s.score,
                             status: s.status, elapsedMinutes: minute, possessionHome: nil,
                             groupLabel: "Premier League", kickoff: t0)
    c.update(followed: live, events: events, lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return nil }
    return p
  }

  func testPanelTimelineMarksGoalsCardsAndVarBySide() throws {
    let s = club()
    let events = [
      MatchEvent(id: "g", fixtureId: 77, minute: 18, extraMinute: nil, team: s.home, player: "Saka", assist: nil, kind: .goal(.normal)),
      MatchEvent(id: "y", fixtureId: 77, minute: 30, extraMinute: nil, team: s.away, player: "Caicedo", assist: nil, kind: .card(.yellow)),
      MatchEvent(id: "s", fixtureId: 77, minute: 40, extraMinute: nil, team: s.away, player: "X", assist: nil, kind: .substitution),
      MatchEvent(id: "r", fixtureId: 77, minute: 44, extraMinute: 2, team: s.home, player: "White", assist: nil, kind: .card(.red)),
      MatchEvent(id: "v", fixtureId: 77, minute: 52, extraMinute: nil, team: s.away, player: nil, assist: nil, kind: .varDecision(detail: "Goal cancelled")),
    ]
    let p = try XCTUnwrap(panelAt(minute: 60, events: events))
    XCTAssertEqual(p.timeline, [
      TimelineMarker(minute: 18, kind: .goal, side: .home),
      TimelineMarker(minute: 30, kind: .yellowCard, side: .away),
      TimelineMarker(minute: 44, kind: .redCard, side: .home),
      TimelineMarker(minute: 52, kind: .varCheck, side: .away),
    ], "substitutions stay off the bar; markers sorted by minute")
    XCTAssertEqual(p.elapsedMinutes, 60)
  }

  func testTimelineFractionSpansNinetyThenStretchesIntoStoppageTime() {
    XCTAssertEqual(TimelineMarker.fraction(minute: 45, elapsed: 60), 0.5, accuracy: 0.001)
    XCTAssertEqual(TimelineMarker.fraction(minute: 90, elapsed: 90), 1.0, accuracy: 0.001)
    XCTAssertEqual(TimelineMarker.fraction(minute: 90, elapsed: 100), 0.9, accuracy: 0.001)
    XCTAssertEqual(TimelineMarker.fraction(minute: 120, elapsed: 100), 1.0, accuracy: 0.001, "clamped")
    XCTAssertEqual(TimelineMarker.fraction(minute: 0, elapsed: nil), 0.0, accuracy: 0.001)
  }

  // MARK: - Pre-match capsule

  func testPanelCarriesKickoffPreMatchFlagAndPrediction() throws {
    var c = HUDComposer()
    c.update(followed: club(.notStarted), events: [], lineups: [], others: [], isStale: false, now: t0)
    c.setPrediction(WinProbability(home: 57, draw: 0, away: 43))
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertTrue(p.isPreMatch)
    XCTAssertEqual(p.kickoff, t0)
    XCTAssertEqual(p.prediction, WinProbability(home: 57, draw: 0, away: 43))
    c.update(followed: club(.firstHalf), events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(live) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertFalse(live.isPreMatch)
  }

  func testWinProbabilityFavouriteLabel() {
    XCTAssertEqual(WinProbability(home: 57, draw: 0, away: 43).favourite, .home)
    XCTAssertEqual(WinProbability(home: 10, draw: 45, away: 45).favourite, .away)
    XCTAssertNil(WinProbability(home: 30, draw: 40, away: 30).favourite, "level: no favourite")
  }

  func testIntroNotRepeatedForSameFixture() {
    var c = HUDComposer()
    feed(&c, club(), at: t0)
    let later = t0.addingTimeInterval(HUDConfig().takeoverSeconds + 1)
    c.tick(now: later)
    feed(&c, club(.firstHalf, score: ScoreLine(home: 1, away: 0)), at: later)
    guard case .panel = c.frame(now: later).body else { return XCTFail("intro must not repeat") }
  }

  func testIntroExpiresAfterTakeoverSeconds() {
    var c = HUDComposer()
    feed(&c, club(), at: t0)
    let after = t0.addingTimeInterval(HUDConfig().takeoverSeconds + 0.1)
    c.tick(now: after)
    guard case .panel = c.frame(now: after).body else { return XCTFail("expected panel after intro") }
  }

  func testGoalPreemptsIntro() {
    var c = HUDComposer()
    feed(&c, club(.firstHalf), at: t0)
    c.enqueue([MatchMoment(fixtureId: 77, kind: .goal(scorer: "Saka", assist: nil, detail: .normal),
                           score: ScoreLine(home: 1, away: 0), minute: 12)], now: t0)
    guard case .takeover = c.frame(now: t0).body else { return XCTFail("goal must pre-empt the intro") }
  }

  func testAnyInputDismissesIntro() {
    var c = HUDComposer()
    feed(&c, club(), at: t0)
    c.handle(.next, now: t0)
    if case .intro = c.frame(now: t0).body { XCTFail("input must dismiss the intro") }
  }

  func testNoIntroInCinemaMode() {
    var c = HUDComposer()
    c.handleTapBurst(count: 3, now: t0)
    feed(&c, club(), at: t0)
    if case .intro = c.frame(now: t0).body { XCTFail("no intro while alerts are paused") }
  }

  func testNoIntroForFinishedMatch() {
    var c = HUDComposer()
    feed(&c, club(.finished), at: t0)
    if case .intro = c.frame(now: t0).body { XCTFail("no intro for a finished match") }
  }

  func testPanelPossessionAwayIsComplement() {
    var c = HUDComposer()
    c.update(followed: snapshot(possession: 72), events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertEqual(p.possessionAway, 28)
    c.update(followed: snapshot(possession: nil), events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(q) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertNil(q.possessionAway)
  }

  func testNationPanelScoreTextKeepsFlags() {
    var c = HUDComposer()
    c.update(followed: snapshot(), events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertEqual(p.scoreText, "🇧🇷 BRA 1 · 0 ARG 🇦🇷")
  }

  func testPanelWithoutCrestHasNilCrest() {
    var c = HUDComposer()
    let snap = MatchSnapshot(fixtureId: 7, home: Team(id: 42, name: "Arsenal"),
                             away: Team(id: 49, name: "Chelsea"), score: ScoreLine(home: 0, away: 0),
                             status: .firstHalf, elapsedMinutes: 3, possessionHome: nil,
                             groupLabel: nil, kickoff: t0)
    c.update(followed: snap, events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail("expected panel") }
    XCTAssertNil(p.homeCrestURL); XCTAssertNil(p.awayCrestURL)
  }

  func testPanelPossessionAndStaleAndGroup() {
    var c = HUDComposer()
    c.update(followed: snapshot(possession: 65), events: [], lineups: [], others: [],
             isStale: true, now: t0)
    guard case let .panel(p) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(p.possessionHome, 65)
    XCTAssertTrue(p.isStale)
    XCTAssertEqual(p.groupLabel, "Group C")
    XCTAssertEqual(p.homeCode, "BRA")
    XCTAssertEqual(p.awayCode, "ARG")
    XCTAssertEqual(p.score, ScoreLine(home: 1, away: 0))
  }

  func testNoFollowedMatchShowsMessage() {
    var c = HUDComposer()
    c.update(followed: nil, events: [], lineups: [], others: [], isStale: false, now: t0)
    guard case .message = c.frame(now: t0).body else { return XCTFail("expected message") }
  }

  // MARK: events / other live ordering

  func testEventsNewestFirstCappedAtEight() {
    var c = HUDComposer()
    let events = (1...10).map { i in
      MatchEvent(id: "e\(i)", fixtureId: 1, minute: i * 5, extraMinute: nil, team: bra,
                 player: "P\(i)", assist: nil, kind: .goal(.normal))
    }
    c.update(followed: snapshot(), events: events, lineups: [], others: [], isStale: false, now: t0)
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    guard case let .events(title, lines) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(title, "Events")
    XCTAssertEqual(lines.count, 8)
    XCTAssertTrue(lines.first!.hasPrefix("50'")) // newest (minute 50) first
  }

  func testOtherLiveSortedByMinuteDesc() {
    var c = HUDComposer()
    let a = MatchSnapshot(fixtureId: 9, home: fra, away: ger, score: ScoreLine(home: 1, away: 1),
                          status: .secondHalf, elapsedMinutes: 55, possessionHome: nil,
                          groupLabel: nil, kickoff: t0)
    let b = MatchSnapshot(fixtureId: 11, home: ger, away: fra, score: ScoreLine(home: 0, away: 0),
                          status: .secondHalf, elapsedMinutes: 80, possessionHome: nil,
                          groupLabel: nil, kickoff: t0)
    c.update(followed: snapshot(), events: [], lineups: [], others: [a, b], isStale: false, now: t0)
    c.handleTapBurst(count: 1, now: t0) // insight
    c.handleTapBurst(count: 1, now: t0) // events
    c.handleTapBurst(count: 1, now: t0) // lineup home
    c.handleTapBurst(count: 1, now: t0) // lineup away
    c.handleTapBurst(count: 1, now: t0) // stats
    c.handleTapBurst(count: 1, now: t0) // other live
    guard case let .otherLive(_, lines) = c.frame(now: t0).body else { return XCTFail() }
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[0].contains("80'"))
    XCTAssertTrue(lines[1].contains("55'"))
  }

  // MARK: Neural Band input (DAT 1.0 Inputs): next / previous / home + listening

  private func bodyKind(_ c: HUDComposer) -> String {
    switch c.frame(now: t0).body {
    case .panel: return "panel"
    case .insight: return "insight"
    case .message(let m): return m == "AI Analyst warming up…" ? "insight" : "message"
    case .events: return "events"
    case .lineup: return "lineup"
    case .playerCard: return "playerCard"
    case .stats: return "stats"
    case .otherLive: return "otherLive"
    case .takeover: return "takeover"
    case .intro: return "intro"
    }
  }

  func testInputNextMatchesSinglePinch() {
    var a = loaded(), b = loaded()
    for _ in 1...4 {
      a.handle(.next, now: t0)
      b.handleTapBurst(count: 1, now: t0)
      XCTAssertEqual(a.frame(now: t0), b.frame(now: t0))
    }
  }

  func testInputPreviousStepsBackThroughDeckAndWraps() {
    var c = loaded()
    c.handle(.previous, now: t0)                 // panel → wraps to other live
    XCTAssertEqual(bodyKind(c), "otherLive")
    c.handle(.previous, now: t0)
    XCTAssertEqual(bodyKind(c), "stats")
    c.handle(.next, now: t0); c.handle(.next, now: t0)
    XCTAssertEqual(bodyKind(c), "panel")
    c.handle(.next, now: t0)
    c.handle(.previous, now: t0)
    XCTAssertEqual(bodyKind(c), "panel")
  }

  func testInputPreviousStepsBackThroughLineupCarousel() {
    var c = loaded()
    for _ in 1...4 { c.handle(.next, now: t0) }   // insight, events, home index, home card 1
    XCTAssertEqual(bodyKind(c), "playerCard")
    c.handle(.previous, now: t0)
    XCTAssertEqual(bodyKind(c), "lineup")         // back to the roster index card
    c.handle(.previous, now: t0)
    XCTAssertEqual(bodyKind(c), "events")         // then to the previous page
  }

  func testInputHomeGoesToPanelAndDismissesTakeover() {
    var c = loaded()
    for _ in 1...4 { c.handle(.next, now: t0) }   // deep in the lineup carousel
    c.handle(.home, now: t0)
    XCTAssertEqual(bodyKind(c), "panel")          // home, no carousel step-back
    c.enqueue([goalMoment()], now: t0)
    XCTAssertEqual(bodyKind(c), "takeover")
    c.handle(.home, now: t0)
    XCTAssertEqual(bodyKind(c), "panel")
  }

  func testListeningBannerOverridesToastUntilCleared() {
    var c = loaded()
    c.enqueue([otherGoal()], now: t0)
    let toast = c.frame(now: t0).toast
    XCTAssertNotNil(toast)
    c.setListening("🎙 Listening… release to ask")
    XCTAssertEqual(c.frame(now: t0).toast, "🎙 Listening… release to ask")
    c.setListening(nil)
    XCTAssertEqual(c.frame(now: t0).toast, toast)
  }
}
