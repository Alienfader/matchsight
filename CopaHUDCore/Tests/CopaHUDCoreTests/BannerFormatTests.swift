import XCTest
@testable import CopaHUDCore

final class BannerFormatTests: XCTestCase {
  func testGoalHeadlinesBecomeOneWord() {
    XCTAssertEqual(BannerFormat.title("GOOOAAALL! ⚽"), "Goal")
    XCTAssertEqual(BannerFormat.title("⚽ GOAL"), "Goal")
  }

  func testOtherHeadlinesAreSentenceCase() {
    XCTAssertEqual(BannerFormat.title("OWN GOAL ⚽"), "Own goal")
    XCTAssertEqual(BannerFormat.title("PENALTY GOAL ⚽"), "Penalty goal")
    XCTAssertEqual(BannerFormat.title("🟥 SENT OFF"), "Sent off")
    XCTAssertEqual(BannerFormat.title("HALF-TIME"), "Half-time")
    XCTAssertEqual(BannerFormat.title("FULL-TIME"), "Full-time")
  }

  func testVarAndPenaltyKeepTheirCodes() {
    XCTAssertEqual(BannerFormat.title("VAR: GOAL STANDS"), "VAR: goal stands")
    XCTAssertEqual(BannerFormat.title("PEN to ARS"), "Penalty, ARS")
  }

  func testDetailSplitsScorerMinuteAndAssist() {
    let d = BannerFormat.detail("Estêvão 28' · assist M. Gusto")
    XCTAssertEqual(d.who, "Estêvão")
    XCTAssertEqual(d.minute, "28′")
    XCTAssertEqual(d.rest, "assist M. Gusto")
  }

  func testDetailWithStoppageTimeAndNoAssist() {
    let d = BannerFormat.detail("B. Saka 90+2'")
    XCTAssertEqual(d.who, "B. Saka")
    XCTAssertEqual(d.minute, "90+2′")
    XCTAssertNil(d.rest)
  }

  func testDetailWithoutMinuteKeepsTheText() {
    let d = BannerFormat.detail("Neymar")
    XCTAssertEqual(d.who, "Neymar")
    XCTAssertNil(d.minute)
    XCTAssertNil(d.rest)
  }
}

final class DeckFormatTests: XCTestCase {
  func testStatRowSplitsLabelAndSides() {
    let r = DeckFormat.statRow("ON TGT  9 · 7")
    XCTAssertEqual(r?.label, "On target")
    XCTAssertEqual(r?.home, "9")
    XCTAssertEqual(r?.away, "7")
    XCTAssertEqual(DeckFormat.statRow("xG  3.00 · 2.30")?.label, "xG")
    XCTAssertEqual(DeckFormat.statRow("SHOTS  – · 4")?.home, "–")
  }

  func testStatRowIgnoresOtherLines() {
    XCTAssertNil(DeckFormat.statRow("no stats yet"))
    XCTAssertNil(DeckFormat.statRow("POSS  ▮▮▮▯▯  55%"))
  }

  func testPossessionReadsThePercentage() {
    XCTAssertEqual(DeckFormat.possession("POSS  ▮▮▮▯▯  55%"), 55)
    XCTAssertNil(DeckFormat.possession("SHOTS  16 · 13"))
  }

  func testOtherLiveRow() {
    let r = DeckFormat.otherLive("LIV 2·0 MCI · 50'")
    XCTAssertEqual(r?.home, "LIV")
    XCTAssertEqual(r?.homeGoals, "2")
    XCTAssertEqual(r?.awayGoals, "0")
    XCTAssertEqual(r?.away, "MCI")
    XCTAssertEqual(r?.clock, "50′")
    XCTAssertNil(DeckFormat.otherLive("BAY 1·1 BVB")?.clock)
    XCTAssertNil(DeckFormat.otherLive("No other live matches"))
  }

  func testMomentumShare() {
    XCTAssertEqual(DeckFormat.share(home: 7, away: 5), 7.0 / 12.0, accuracy: 0.0001)
    XCTAssertEqual(DeckFormat.share(home: 0, away: 0), 0.5)
  }
}
