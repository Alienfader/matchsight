import XCTest
@testable import CopaHUDCore

/// PollPlanner is the poll-cadence policy: followed 15s · half-time 60s ·
/// others 60s · poll window opens kickoff−120s · nothing to poll → nil.
final class PollPlannerTests: XCTestCase {
  // MARK: followedInterval

  func testFollowedLiveIs15s() {
    XCTAssertEqual(PollPlanner.followedInterval(status: .firstHalf), 15)
    XCTAssertEqual(PollPlanner.followedInterval(status: .secondHalf), 15)
    XCTAssertEqual(PollPlanner.followedInterval(status: .extraTime), 15)
    XCTAssertEqual(PollPlanner.followedInterval(status: .penalties), 15)
    XCTAssertEqual(PollPlanner.followedInterval(status: .live), 15)
  }

  func testFollowedHalfTimeIs60s() {
    XCTAssertEqual(PollPlanner.followedInterval(status: .halfTime), 60)
  }

  func testFollowedNotLiveIsNil() {
    XCTAssertNil(PollPlanner.followedInterval(status: .notStarted))
    XCTAssertNil(PollPlanner.followedInterval(status: .finished))
    XCTAssertNil(PollPlanner.followedInterval(status: .finishedAfterPens))
    XCTAssertNil(PollPlanner.followedInterval(status: .postponed))
  }

  // MARK: othersInterval

  func testOthersInterval() {
    XCTAssertEqual(PollPlanner.othersInterval(anyLive: true), 60)
    XCTAssertNil(PollPlanner.othersInterval(anyLive: false))
  }

  // MARK: nextPollWindow

  private func fixture(_ id: Int, kickoff: TimeInterval, status: MatchStatus) -> Fixture {
    Fixture(id: id, kickoff: Date(timeIntervalSince1970: kickoff),
            home: Team(id: 1, name: "Home"), away: Team(id: 2, name: "Away"),
            groupLabel: nil, venue: nil, status: status)
  }

  func testNextPollWindowEmptyIsNil() {
    XCTAssertNil(PollPlanner.nextPollWindow(fixtures: [], now: Date(timeIntervalSince1970: 1000)))
  }

  func testNextPollWindowAllFinishedIsNil() {
    let fx = [fixture(1, kickoff: 2000, status: .finished),
              fixture(2, kickoff: 3000, status: .finishedAfterExtra)]
    XCTAssertNil(PollPlanner.nextPollWindow(fixtures: fx, now: Date(timeIntervalSince1970: 1000)))
  }

  func testNextPollWindowOpensTwoMinutesBeforeEarliestFutureKickoff() {
    let fx = [fixture(1, kickoff: 2000, status: .notStarted),
              fixture(2, kickoff: 1500, status: .notStarted)]
    let win = PollPlanner.nextPollWindow(fixtures: fx, now: Date(timeIntervalSince1970: 1000))
    XCTAssertEqual(win, Date(timeIntervalSince1970: 1500 - 120))
  }

  func testNextPollWindowIgnoresKickoffsWhoseWindowAlreadyOpened() {
    // kickoff 1050 → window 930, already before now=1000, so it's filtered out;
    // the next future one (kickoff 2000 → window 1880) wins.
    let fx = [fixture(1, kickoff: 1050, status: .notStarted),
              fixture(2, kickoff: 2000, status: .notStarted)]
    let win = PollPlanner.nextPollWindow(fixtures: fx, now: Date(timeIntervalSince1970: 1000))
    XCTAssertEqual(win, Date(timeIntervalSince1970: 2000 - 120))
  }

  func testNextPollWindowMixedPastFutureAndFinished() {
    let fx = [fixture(1, kickoff: 500, status: .finished),     // past + finished → ignored
              fixture(2, kickoff: 900, status: .notStarted),   // window 780 < now → ignored
              fixture(3, kickoff: 5000, status: .notStarted),  // future
              fixture(4, kickoff: 4000, status: .notStarted)]  // earlier future → wins
    let win = PollPlanner.nextPollWindow(fixtures: fx, now: Date(timeIntervalSince1970: 1000))
    XCTAssertEqual(win, Date(timeIntervalSince1970: 4000 - 120))
  }

  func testNextPollWindowAllWindowsPastIsNil() {
    let fx = [fixture(1, kickoff: 1050, status: .notStarted),
              fixture(2, kickoff: 1100, status: .notStarted)]
    // both windows (930, 980) already opened before now=1000.
    XCTAssertNil(PollPlanner.nextPollWindow(fixtures: fx, now: Date(timeIntervalSince1970: 1000)))
  }
}
