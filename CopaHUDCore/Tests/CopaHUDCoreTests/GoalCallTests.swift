import XCTest
@testable import CopaHUDCore

/// The spoken goal call: only facts from the feed (scorer, minute, score),
/// read after the chime.
final class GoalCallTests: XCTestCase {
  let mun = Team(id: 33, name: "Manchester United")
  let rom = Team(id: 497, name: "AS Roma")

  private func goal(_ scorer: String?, _ detail: MatchEvent.GoalDetail = .normal,
                    home: Int, away: Int, minute: Int? = 67) -> MatchMoment {
    MatchMoment(fixtureId: 1, kind: .goal(scorer: scorer, assist: nil, detail: detail),
                score: ScoreLine(home: home, away: away), minute: minute)
  }

  func testAGoalNamesTheScorerMinuteAndWhoLeads() {
    XCTAssertEqual(GoalCall.text(goal("B. Fernandes", home: 2, away: 1), home: mun, away: rom),
                   "Goal! Fernandes, 67 minutes. Manchester United lead two one.")
    XCTAssertEqual(GoalCall.text(goal("P. Dybala", home: 0, away: 1), home: mun, away: rom),
                   "Goal! Dybala, 67 minutes. AS Roma lead one nil.")
  }

  func testALevelScore() {
    XCTAssertEqual(GoalCall.text(goal("Casemiro", home: 1, away: 1), home: mun, away: rom),
                   "Goal! Casemiro, 67 minutes. All square, one all.")
  }

  func testPenaltiesAndOwnGoalsSaySo() {
    XCTAssertEqual(GoalCall.text(goal("B. Fernandes", .penalty, home: 1, away: 0), home: mun, away: rom),
                   "Goal! Fernandes, from the penalty spot, 67 minutes. Manchester United lead one nil.")
    XCTAssertEqual(GoalCall.text(goal("G. Mancini", .ownGoal, home: 1, away: 0), home: mun, away: rom),
                   "Own goal! Mancini, 67 minutes. Manchester United lead one nil.")
  }

  func testUnknownScorerOrMinuteAreLeftOut() {
    XCTAssertEqual(GoalCall.text(goal(nil, home: 1, away: 0, minute: nil), home: mun, away: rom),
                   "Goal! Manchester United lead one nil.")
    XCTAssertEqual(GoalCall.text(goal("Casemiro", home: 1, away: 0, minute: 90), home: mun, away: rom),
                   "Goal! Casemiro, 90 minutes. Manchester United lead one nil.")
  }

  func testBigScoresUseFigures() {
    XCTAssertEqual(GoalCall.text(goal("Højlund", home: 11, away: 0), home: mun, away: rom),
                   "Goal! Højlund, 67 minutes. Manchester United lead 11 nil.")
  }

  func testNothingElseIsCalled() {
    let missed = goal("B. Fernandes", .missedPenalty, home: 0, away: 0)
    XCTAssertNil(GoalCall.text(missed, home: mun, away: rom))
    let red = MatchMoment(fixtureId: 1, kind: .redCard(player: "Casemiro", team: mun),
                          score: ScoreLine(home: 0, away: 0), minute: 50)
    XCTAssertNil(GoalCall.text(red, home: mun, away: rom))
  }
}
