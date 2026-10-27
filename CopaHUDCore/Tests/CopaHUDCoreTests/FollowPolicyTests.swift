import XCTest
@testable import CopaHUDCore

final class FollowPolicyTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_793_000_000)
  let ars = Team(id: 42, name: "Arsenal"), che = Team(id: 49, name: "Chelsea")
  let liv = Team(id: 40, name: "Liverpool"), mci = Team(id: 50, name: "Manchester City")
  let mun = Team(id: 33, name: "Manchester United"), tot = Team(id: 47, name: "Tottenham")

  func fx(_ id: Int, kickoffMinutesAgo: Double, _ home: Team, _ away: Team,
          _ status: MatchStatus = .firstHalf) -> Fixture {
    Fixture(id: id, kickoff: now.addingTimeInterval(-kickoffMinutesAgo * 60), home: home, away: away,
            groupLabel: nil, competition: "Premier League", venue: nil, status: status)
  }

  func decide(_ fixtures: [Fixture], _ favourites: Set<Int>, _ state: FollowState = FollowState(),
              at t: Date? = nil) -> FollowDecision {
    FollowPolicy.decide(fixtures: fixtures, favourites: favourites, state: state, now: t ?? now)
  }

  func testFollowsLiveFavourite() {
    XCTAssertEqual(decide([fx(1, kickoffMinutesAgo: 20, ars, che), fx(2, kickoffMinutesAgo: 20, mun, tot)], [33]),
                   .follow(2))
  }

  func testEarliestKickoffWinsWhenTwoFavouritesLive() {
    let early = fx(9, kickoffMinutesAgo: 60, liv, mci), late = fx(3, kickoffMinutesAgo: 10, ars, che)
    XCTAssertEqual(decide([late, early], [42, 40]), .follow(9))
  }

  func testTieOnKickoffBreaksByLowestId() {
    XCTAssertEqual(decide([fx(8, kickoffMinutesAgo: 30, ars, che), fx(5, kickoffMinutesAgo: 30, liv, mci)], [42, 40]),
                   .follow(5))
  }

  func testNeverSwapsAutoFollowedLiveMatch() {
    let a = fx(1, kickoffMinutesAgo: 150, ars, che), b = fx(2, kickoffMinutesAgo: 60, liv, mci)
    XCTAssertEqual(decide([a, b], [42, 40], FollowState(fixtureId: 2)), .keep)
  }

  func testManualFollowWins() {
    let other = fx(1, kickoffMinutesAgo: 30, mun, tot), fav = fx(2, kickoffMinutesAgo: 5, ars, che)
    XCTAssertEqual(decide([other, fav], [42], FollowState(fixtureId: 1, isManual: true)), .keep)
  }

  func testUnfollowedFixtureIsSuppressed() {
    let a = fx(1, kickoffMinutesAgo: 30, ars, che), b = fx(2, kickoffMinutesAgo: 10, liv, mci)
    XCTAssertEqual(decide([a, b], [42, 40], FollowState(suppressed: [1])), .follow(2))
    XCTAssertEqual(decide([a], [42], FollowState(suppressed: [1])), .keep)
  }

  func testFollowsWithinPreKickoffWindow() {
    XCTAssertEqual(decide([fx(1, kickoffMinutesAgo: -4, ars, che, .notStarted)], [42]), .follow(1))
  }

  func testIgnoresBeyondPreKickoffWindow() {
    XCTAssertEqual(decide([fx(1, kickoffMinutesAgo: -6, ars, che, .notStarted)], [42]), .keep)
  }

  func testHoldsFinalScoreFor120Seconds() {
    let done = fx(1, kickoffMinutesAgo: 115, ars, che, .finished), other = fx(2, kickoffMinutesAgo: 30, liv, mci)
    let state = FollowState(fixtureId: 1, finishedAt: now.addingTimeInterval(-119))
    XCTAssertEqual(decide([done, other], [42, 40], state), .keep)
  }

  func testSwitchesAfterHold() {
    let done = fx(1, kickoffMinutesAgo: 115, ars, che, .finished), other = fx(2, kickoffMinutesAgo: 30, liv, mci)
    let state = FollowState(fixtureId: 1, isManual: true, finishedAt: now.addingTimeInterval(-121))
    XCTAssertEqual(decide([done, other], [42, 40], state), .follow(2))
  }

  func testStaysOnFinalScoreWhenNoOtherFavourite() {
    let done = fx(1, kickoffMinutesAgo: 125, ars, che, .finished)
    XCTAssertEqual(decide([done], [42], FollowState(fixtureId: 1, finishedAt: now.addingTimeInterval(-600))), .keep)
  }

  // MARK: Review Focus

  func testKeepsAutoFollowWhenCurrentMissingFromList() {
    let b = fx(2, kickoffMinutesAgo: 30, liv, mci)
    XCTAssertEqual(decide([b], [42, 40], FollowState(fixtureId: 1)), .keep)
  }

  func testFixtureBetweenTwoFavouritesIsOneCandidate() {
    XCTAssertEqual(decide([fx(1, kickoffMinutesAgo: 30, ars, che)], [42, 49]), .follow(1))
  }

  func testSkipsPostponedAndCancelled() {
    let fixtures = [fx(1, kickoffMinutesAgo: 60, ars, che, .postponed),
                    fx(2, kickoffMinutesAgo: 50, liv, mci, .cancelled),
                    fx(3, kickoffMinutesAgo: 40, mun, tot, .abandoned)]
    XCTAssertEqual(decide(fixtures, [42, 40, 33]), .keep)
    XCTAssertEqual(decide(fixtures + [fx(4, kickoffMinutesAgo: 10, Team(id: 1, name: "X"), ars)], [42, 40, 33]),
                   .follow(4))
  }

  // MARK: - a followed match that ends any way (review fix)

  func testIsOverCoversEveryTerminalStatus() {
    for s: MatchStatus in [.finished, .finishedAfterExtra, .finishedAfterPens,
                           .abandoned, .cancelled, .postponed, .technicalLoss, .walkover] {
      XCTAssertTrue(s.isOver, "\(s)")
    }
    for s: MatchStatus in [.notStarted, .firstHalf, .halfTime, .suspended, .interrupted, .unknown] {
      XCTAssertFalse(s.isOver, "\(s)")
    }
  }

  func testAbandonedFollowedMatchIsReleasedAfterHold() {
    let other = fx(2, kickoffMinutesAgo: 20, liv, mci)
    var state = FollowState(fixtureId: 1)
    state.noteFollowedStatus(.abandoned, fixtureId: 1, now: now)
    XCTAssertEqual(state.finishedAt, now)
    XCTAssertEqual(decide([other], [42, 40], state), .keep)
    XCTAssertEqual(decide([other], [42, 40], state, at: now.addingTimeInterval(FollowPolicy.fullTimeHold)),
                   .follow(2))
  }

  func testNoteFollowedStatusIgnoresOtherFixturesAndKeepsFirstTime() {
    var state = FollowState(fixtureId: 1)
    state.noteFollowedStatus(.finished, fixtureId: 7, now: now)
    XCTAssertNil(state.finishedAt)
    state.noteFollowedStatus(.secondHalf, fixtureId: 1, now: now)
    XCTAssertNil(state.finishedAt)
    state.noteFollowedStatus(.postponed, fixtureId: 1, now: now)
    state.noteFollowedStatus(.postponed, fixtureId: 1, now: now.addingTimeInterval(60))
    XCTAssertEqual(state.finishedAt, now)
  }
}
