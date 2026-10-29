import XCTest
@testable import CopaHUDCore

/// First connection: one page per Neural Band gesture, each waiting for the
/// fan to do it, before the deck. The deck doesn't move meanwhile.
final class GestureGuideTests: XCTestCase {
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  private func guide(_ c: HUDComposer) -> GuideContent? {
    if case let .guide(g) = c.frame(now: t0).body { return g }
    return nil
  }

  func testEachStepWaitsForItsGesture() {
    var c = HUDComposer()
    c.startGestureGuide()
    XCTAssertEqual(guide(c)?.step, 1)
    XCTAssertEqual(guide(c)?.total, GestureGuide.steps.count)
    XCTAssertEqual(guide(c)?.action, "Swipe right")

    c.handle(.previous, now: t0)            // the wrong one
    XCTAssertEqual(guide(c)?.step, 1)
    XCTAssertEqual(guide(c)?.tryAgain, true)

    c.handle(.next, now: t0)                // swipe right
    XCTAssertEqual(guide(c)?.step, 2)
    XCTAssertEqual(guide(c)?.tryAgain, false)
    c.handle(.previous, now: t0)            // swipe left
    c.handle(.home, now: t0)                // swipe up
    c.handle(.insight, now: t0)             // swipe down
    c.handle(.select, now: t0)              // pinch
    XCTAssertEqual(guide(c)?.action, "Pinch and hold")
    c.guideHoldDone()                       // a hold to ask
    XCTAssertNil(guide(c), "done: the deck is back")
    XCTAssertFalse(c.isGuiding)
  }

  func testTheDeckStaysOnThePanelDuringTheGuide() {
    var c = HUDComposer()
    c.startGestureGuide()
    for input in [HUDInput.next, .previous, .home, .insight, .select] { c.handle(input, now: t0) }
    c.guideHoldDone()
    XCTAssertEqual(c.frame(now: t0).deck?.index, 0)
  }

  func testTheGuideCanBeSkippedWithAHold() {
    // Holding from any step ends it: the fan already knows the band.
    var c = HUDComposer()
    c.startGestureGuide()
    c.guideHoldDone()
    XCTAssertFalse(c.isGuiding)
  }

  func testAGoalBannerStillShowsOverTheGuide() {
    var c = HUDComposer()
    c.startGestureGuide()
    c.enqueue([MatchMoment(fixtureId: 1, kind: .fullTime, score: ScoreLine(home: 0, away: 0), minute: 90)],
              now: t0)
    guard case .takeover = c.frame(now: t0).body else { return XCTFail("banner first") }
  }
}
