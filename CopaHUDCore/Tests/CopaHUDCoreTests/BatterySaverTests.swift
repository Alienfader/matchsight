import XCTest
@testable import CopaHUDCore

/// Battery saver: after a quiet spell with no gestures and nothing happening,
/// the glasses drop to a near-black score line (dim) or the display turns off
/// (display off). Any gesture, goal banner, toast or voice step wakes them.
final class BatterySaverTests: XCTestCase {
  let bra = Team(id: 6, name: "Brazil")
  let arg = Team(id: 26, name: "Argentina")
  let fra = Team(id: 2, name: "France")
  let ger = Team(id: 25, name: "Germany")
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)
  private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

  private func composer(_ saver: BatterySaver) -> HUDComposer {
    var c = HUDComposer(config: HUDConfig(batterySaver: saver, idleSeconds: 20))
    let snap = MatchSnapshot(fixtureId: 1, home: bra, away: arg, score: ScoreLine(home: 1, away: 0),
                             status: .firstHalf, elapsedMinutes: 30, possessionHome: nil,
                             groupLabel: nil, kickoff: t0)
    c.update(followed: snap, events: [], lineups: [], others: [], isStale: false, now: t0)
    c.tick(now: t0)
    return c
  }

  private func isQuiet(_ f: HUDFrame) -> Bool {
    if case .quiet = f.body { return true }
    return false
  }

  private func goal() -> MatchMoment {
    MatchMoment(fixtureId: 1, kind: .goal(scorer: "Neymar", assist: nil, detail: .normal),
                score: ScoreLine(home: 2, away: 0), minute: 67)
  }

  func testOffNeverGoesQuiet() {
    var c = composer(.off)
    c.tick(now: at(600))
    let f = c.frame(now: at(600))
    XCTAssertFalse(isQuiet(f))
    XCTAssertFalse(f.displayOff)
  }

  func testDimGoesQuietAfterTheIdleSpell() {
    var c = composer(.dim)
    c.tick(now: at(19))
    XCTAssertFalse(isQuiet(c.frame(now: at(19))))
    c.tick(now: at(20))
    let f = c.frame(now: at(20))
    guard case let .quiet(q) = f.body else { return XCTFail("expected the quiet page") }
    XCTAssertTrue(q.scoreLine?.contains("1 · 0") ?? false, q.scoreLine ?? "nil")
    XCTAssertEqual(q.clock, "30'")
    XCTAssertNil(f.deck, "no page dots on the quiet page")
    XCTAssertFalse(f.displayOff)
  }

  func testDisplayOffAsksTheAppToTurnTheDisplayOff() {
    var c = composer(.displayOff)
    c.tick(now: at(25))
    let f = c.frame(now: at(25))
    XCTAssertTrue(f.displayOff)
    XCTAssertTrue(isQuiet(f))
  }

  func testTheFirstGestureOnlyWakes() {
    var c = composer(.dim)
    c.handle(.next, now: at(5))           // panel → insight while awake
    c.tick(now: at(40))
    XCTAssertTrue(isQuiet(c.frame(now: at(40))))
    c.handle(.next, now: at(41))          // wakes, stays on insight
    var f = c.frame(now: at(41))
    XCTAssertFalse(isQuiet(f))
    XCTAssertEqual(f.deck?.index, 1)
    c.handle(.next, now: at(42))          // awake: moves on
    f = c.frame(now: at(42))
    XCTAssertEqual(f.deck?.index, 2)
  }

  func testATapBurstAlsoOnlyWakes() {
    var c = composer(.dim)
    c.tick(now: at(40))
    c.handleTapBurst(count: 1, now: at(41))
    XCTAssertEqual(c.frame(now: at(41)).deck?.index, 0, "still on the panel")
  }

  func testGestureKeepsItAwake() {
    var c = composer(.dim)
    c.handle(.next, now: at(15))
    c.tick(now: at(30))
    XCTAssertFalse(isQuiet(c.frame(now: at(30))), "20 s from the last gesture, not from the start")
    c.tick(now: at(35))
    XCTAssertTrue(isQuiet(c.frame(now: at(35))))
  }

  func testAGoalBannerWakesAndTheSpellRestartsAfterIt() {
    var c = composer(.displayOff)
    c.tick(now: at(30))
    XCTAssertTrue(c.frame(now: at(30)).displayOff)
    c.enqueue([goal()], now: at(31))
    c.tick(now: at(31))
    var f = c.frame(now: at(31))
    guard case .takeover = f.body else { return XCTFail("the goal banner shows") }
    XCTAssertFalse(f.displayOff)
    // The banner holds 8 s (to 39 s); the panel then stays up for 20 s more.
    c.tick(now: at(45))
    f = c.frame(now: at(45))
    guard case .panel = f.body else { return XCTFail("back to the panel after the banner") }
    c.tick(now: at(58))
    XCTAssertFalse(c.frame(now: at(58)).displayOff)
    c.tick(now: at(60))
    XCTAssertTrue(c.frame(now: at(60)).displayOff)
  }

  func testAVoiceBannerWakes() {
    var c = composer(.displayOff)
    c.tick(now: at(30))
    c.setListening("🎙 Listening… release to ask")
    c.tick(now: at(31))
    let f = c.frame(now: at(31))
    XCTAssertFalse(f.displayOff)
    XCTAssertEqual(f.toast, "🎙 Listening… release to ask")
  }

  func testAnOtherMatchToastWakes() {
    var c = composer(.dim)
    c.tick(now: at(30))
    let snap = MatchSnapshot(fixtureId: 9, home: fra, away: ger, score: ScoreLine(home: 1, away: 0),
                             status: .secondHalf, elapsedMinutes: 80, possessionHome: nil,
                             groupLabel: nil, kickoff: t0)
    c.enqueue([MatchMoment(fixtureId: 9, kind: .otherMatchGoal(snapshot: snap, scorer: "Mbappé"),
                           score: ScoreLine(home: 1, away: 0), minute: 80)], now: at(31))
    c.tick(now: at(31))
    let f = c.frame(now: at(31))
    XCTAssertFalse(isQuiet(f))
    XCTAssertNotNil(f.toast)
  }

  func testAPhoneJumpWakes() {
    var c = composer(.dim)
    c.tick(now: at(30))
    c.showInsightPage()
    c.tick(now: at(31))
    let f = c.frame(now: at(31))
    XCTAssertFalse(isQuiet(f))
    XCTAssertEqual(f.deck?.index, 1)
  }

  func testANewSpokenAnswerOnTheInsightPageWakes() {
    var c = composer(.dim)
    c.showInsightPage()
    c.setInsight(InsightContent(title: "Thinking…", body: "", footer: "Muse Spark", question: "who scored?"))
    c.tick(now: at(1))
    c.tick(now: at(30))
    XCTAssertTrue(isQuiet(c.frame(now: at(30))), "a slow answer can let it go quiet")
    c.setInsight(InsightContent(title: "Neymar", body: "Scored on 12'.", footer: "Muse Spark",
                                question: "who scored?"))
    c.tick(now: at(31))
    XCTAssertFalse(isQuiet(c.frame(now: at(31))), "the answer wakes it")
  }

  func testAnAutomaticInsightRefreshDoesNotWake() {
    var c = composer(.dim)
    c.showInsightPage()
    c.tick(now: at(1))
    c.tick(now: at(30))
    c.setInsight(InsightContent(title: "Pressing high", body: "…", footer: "Muse Spark"))
    c.tick(now: at(31))
    XCTAssertTrue(isQuiet(c.frame(now: at(31))))
  }

  func testReactivateFromThePhoneWakes() {
    var c = composer(.displayOff)
    c.tick(now: at(30))
    c.wake()
    c.tick(now: at(31))
    XCTAssertFalse(c.frame(now: at(31)).displayOff)
  }

  func testTheQuietClockStillMoves() {
    var c = composer(.dim)
    c.tick(now: at(30))
    guard case let .quiet(a) = c.frame(now: at(30)).body else { return XCTFail() }
    c.tick(now: at(95))
    guard case let .quiet(b) = c.frame(now: at(95)).body else { return XCTFail() }
    XCTAssertEqual(a.clock, "30'")
    XCTAssertEqual(b.clock, "31'")
  }
}
