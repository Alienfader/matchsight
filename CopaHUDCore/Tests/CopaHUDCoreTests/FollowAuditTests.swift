import XCTest
@testable import CopaHUDCore

final class FollowAuditTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_793_000_000)
  let ars = Team(id: 42, name: "Arsenal"), che = Team(id: 49, name: "Chelsea")
  let liv = Team(id: 40, name: "Liverpool"), mci = Team(id: 50, name: "Manchester City")
  let mun = Team(id: 33, name: "Manchester United"), tot = Team(id: 47, name: "Tottenham")

  func fx(_ id: Int, kickoffMinutesAgo: Double, _ home: Team, _ away: Team,
          _ status: MatchStatus = .firstHalf) -> Fixture {
    Fixture(id: id, kickoff: now.addingTimeInterval(-kickoffMinutesAgo * 60), home: home, away: away,
            groupLabel: nil, competition: "Premier League", venue: nil, status: status)
  }

  func check(_ fixtures: [Fixture], _ favourites: Set<Int>, followed: Int?, manual: Bool = false,
             suppressed: Set<Int> = [], shown: Int? = nil) -> [FollowAudit.Finding] {
    let state = FollowState(fixtureId: followed, isManual: manual, suppressed: suppressed)
    return FollowAudit.check(fixtures: fixtures, favourites: favourites, state: state,
                             shownFixtureId: shown, now: now)
  }

  func testFollowingTheLiveFavouriteIsClean() {
    XCTAssertEqual(check([fx(1, kickoffMinutesAgo: 20, ars, che)], [42], followed: 1, shown: 1), [])
  }

  func testNothingLiveAndNothingFollowedIsClean() {
    XCTAssertEqual(check([fx(1, kickoffMinutesAgo: -120, ars, che, .notStarted)], [42], followed: nil), [])
  }

  func testLiveFavouriteButNothingFollowed() {
    XCTAssertEqual(check([fx(1, kickoffMinutesAgo: 20, ars, che)], [42], followed: nil),
                   [.notFollowing(live: 1)])
  }

  func testUnfollowedFavouriteIsNotFlagged() {
    XCTAssertEqual(check([fx(1, kickoffMinutesAgo: 20, ars, che)], [42], followed: nil, suppressed: [1]), [])
  }

  func testAutoFollowOfANonFavouriteMatch() {
    XCTAssertEqual(check([fx(2, kickoffMinutesAgo: 20, mun, tot)], [42], followed: 2),
                   [.notAFavourite(followed: 2)])
  }

  func testManualFollowOfAnyMatchIsTheFansChoice() {
    let fixtures = [fx(1, kickoffMinutesAgo: 60, ars, che), fx(2, kickoffMinutesAgo: 20, mun, tot)]
    XCTAssertEqual(check(fixtures, [42], followed: 2, manual: true), [])
  }

  func testLaterKickoffFollowedWhileEarlierFavouriteIsLive() {
    let early = fx(9, kickoffMinutesAgo: 60, liv, mci), late = fx(3, kickoffMinutesAgo: 10, ars, che)
    XCTAssertEqual(check([late, early], [42, 40], followed: 3),
                   [.laterKickoff(followed: 3, earlier: 9)])
  }

  func testEarlierFavouriteThatHasFinishedIsNotFlagged() {
    let early = fx(9, kickoffMinutesAgo: 120, liv, mci, .finished), late = fx(3, kickoffMinutesAgo: 10, ars, che)
    XCTAssertEqual(check([late, early], [42, 40], followed: 3), [])
  }

  func testGlassesShowingAnotherMatchesData() {
    XCTAssertEqual(check([fx(1, kickoffMinutesAgo: 20, ars, che)], [42], followed: 1, shown: 7),
                   [.shownMismatch(followed: 1, shown: 7)])
  }

  func testFollowedMatchMissingFromTheListIsNotJudged() {
    // A poll can drop the followed match from today's list; FollowPolicy keeps it.
    XCTAssertEqual(check([], [42], followed: 1), [])
  }

  func testLogLineIsStableAndGreppable() {
    XCTAssertEqual(FollowAudit.logLine([], followed: 1), "audit: ok followed=1")
    XCTAssertEqual(FollowAudit.logLine([], followed: nil), "audit: ok followed=none")
    XCTAssertEqual(FollowAudit.logLine([.notAFavourite(followed: 2), .shownMismatch(followed: 2, shown: 7)],
                                       followed: 2),
                   "audit: WRONG followed=2 not-a-favourite(2) shown-mismatch(2≠7)")
  }
}
