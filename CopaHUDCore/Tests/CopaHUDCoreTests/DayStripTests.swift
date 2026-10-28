import XCTest
@testable import CopaHUDCore

final class DayStripTests: XCTestCase {
  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
  }
  // Wed 28 Oct 2026, 10:00 New York.
  private let now = Date(timeIntervalSince1970: 1_793_196_000)

  func testYesterdayThroughSevenDaysAhead() {
    let days = DayStrip.days(now: now, calendar: calendar)
    XCTAssertEqual(days.count, 9)
    XCTAssertEqual(days.first, calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
    XCTAssertEqual(days[1], calendar.startOfDay(for: now))
    XCTAssertEqual(days.last, calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)))
  }

  func testEveryDayIsMidnight() {
    for day in DayStrip.days(now: now, calendar: calendar) {
      XCTAssertEqual(day, calendar.startOfDay(for: day))
    }
  }

  func testCrossesTheEndOfDaylightSavingTime() {
    // US clocks go back on Sun 1 Nov 2026: that day still appears once.
    let days = DayStrip.days(now: now, calendar: calendar)
    let labels = days.map { calendar.component(.day, from: $0) }
    XCTAssertEqual(labels, [27, 28, 29, 30, 31, 1, 2, 3, 4])
  }

  func testIsToday() {
    XCTAssertTrue(DayStrip.isToday(calendar.startOfDay(for: now), now: now, calendar: calendar))
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    XCTAssertFalse(DayStrip.isToday(tomorrow, now: now, calendar: calendar))
  }
}
