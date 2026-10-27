import XCTest
@testable import CopaHUDCore

/// smoke tests: the shared contract compiles, decodes leniently, and
/// the stubs are inert. Squad branches replace the stubs with real suites.
final class ContractTests: XCTestCase {
  func testMatchStatusDecodesUnknownCodesLeniently() throws {
    let decoded = try JSONDecoder().decode([MatchStatus].self,
                                           from: Data(#"["1H","HT","FT","WTF"]"#.utf8))
    XCTAssertEqual(decoded, [.firstHalf, .halfTime, .finished, .unknown])
  }

  func testMatchStatusLiveness() {
    XCTAssertTrue(MatchStatus.firstHalf.isLive)
    XCTAssertTrue(MatchStatus.halfTime.isLive)
    XCTAssertFalse(MatchStatus.notStarted.isLive)
    XCTAssertTrue(MatchStatus.finishedAfterPens.isFinished)
    XCTAssertFalse(MatchStatus.halfTime.isFinished)
  }

  func testMatchEventRoundTripsThroughJSON() throws {
    let event = MatchEvent(
      id: "1-67+0-6-Goal-Normal Goal-276", fixtureId: 1, minute: 67,
      extraMinute: nil, team: Team(id: 6, name: "Brazil"),
      player: "Neymar", assist: "Vinícius Júnior", kind: .goal(.normal))
    let data = try JSONEncoder().encode(event)
    XCTAssertEqual(try JSONDecoder().decode(MatchEvent.self, from: data), event)
  }

  func testEngineStubIsInert() {
    var engine = MatchEngine()
    let snapshot = MatchSnapshot(
      fixtureId: 1, home: Team(id: 6, name: "Brazil"), away: Team(id: 26, name: "Argentina"),
      score: ScoreLine(home: 0, away: 0), status: .firstHalf, elapsedMinutes: 10,
      possessionHome: nil, groupLabel: nil, kickoff: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(engine.ingestFollowed(snapshot: snapshot, events: []), [])
    XCTAssertEqual(engine.ingestOthers([snapshot]), [])
  }

  func testPollPlannerCadence() {
    XCTAssertEqual(PollPlanner.followedInterval(status: .firstHalf), 15)
    XCTAssertEqual(PollPlanner.followedInterval(status: .halfTime), 60)
    XCTAssertNil(PollPlanner.followedInterval(status: .notStarted))
    XCTAssertNil(PollPlanner.followedInterval(status: .finished))
    XCTAssertEqual(PollPlanner.othersInterval(anyLive: true), 60)
    XCTAssertNil(PollPlanner.othersInterval(anyLive: false))
  }

  func testComposerStubEmitsAFrame() {
    var composer = HUDComposer()
    composer.tick(now: Date(timeIntervalSince1970: 0))
    if case .message = composer.frame(now: Date(timeIntervalSince1970: 0)).body {} else {
      XCTFail("stub composer should emit a message frame")
    }
  }
}
