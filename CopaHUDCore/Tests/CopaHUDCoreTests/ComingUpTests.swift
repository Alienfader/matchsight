import XCTest
@testable import CopaHUDCore

final class ComingUpTests: XCTestCase {
  private let ars = Team(id: 42, name: "Arsenal")
  private let che = Team(id: 49, name: "Chelsea")
  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
  }
  // Tue 28 Oct 2026, 10:00 New York.
  private let now = Date(timeIntervalSince1970: 1_793_196_000)

  private func fixture(_ id: Int, hoursFromNow: Double, status: MatchStatus = .notStarted) -> Fixture {
    Fixture(id: id, kickoff: now.addingTimeInterval(hoursFromNow * 3600), home: ars, away: che,
            groupLabel: nil, venue: nil, status: status)
  }

  func testStartsTomorrowAndKeepsKickoffOrder() {
    let list = ComingUp.list([fixture(3, hoursFromNow: 24 * 20), fixture(1, hoursFromNow: 6),
                              fixture(2, hoursFromNow: 15)],
                             now: now, calendar: calendar)
    // 6 h from now is still today (16:00); 15 h is tomorrow 01:00.
    XCTAssertEqual(list.map(\.id), [2, 3])
  }

  func testDropsFinishedAndPastFixtures() {
    let list = ComingUp.list([fixture(1, hoursFromNow: 48, status: .postponed),
                              fixture(2, hoursFromNow: -48), fixture(3, hoursFromNow: 72)],
                             now: now, calendar: calendar)
    XCTAssertEqual(list.map(\.id), [3])
  }
}
