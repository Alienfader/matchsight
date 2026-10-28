import XCTest
@testable import CopaHUDCore

/// The TV delay: feed updates wait until the broadcast has caught up, so the
/// glasses never show a goal before the TV does.
final class BroadcastDelayTests: XCTestCase {
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  func testZeroDelayReleasesAtOnce() {
    var line = BroadcastDelay<String>()
    line.push("a", at: t0)
    XCTAssertEqual(line.due(now: t0), ["a"])
    XCTAssertEqual(line.due(now: t0), [])
  }

  func testItemsWaitForTheDelayThenLeaveInOrder() {
    var line = BroadcastDelay<String>(seconds: 30)
    line.push("a", at: t0)
    line.push("b", at: t0.addingTimeInterval(10))
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(29)), [])
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(30)), ["a"])
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(45)), ["b"])
    XCTAssertTrue(line.isEmpty)
  }

  func testShorteningTheDelayReleasesWhatIsNowDue() {
    var line = BroadcastDelay<String>(seconds: 60)
    line.push("a", at: t0)
    line.push("b", at: t0.addingTimeInterval(20))
    line.seconds = 15
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(30)), ["a"])
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(35)), ["b"])
  }

  func testClearDropsEverything() {
    var line = BroadcastDelay<String>(seconds: 30)
    line.push("a", at: t0)
    line.clear()
    XCTAssertEqual(line.due(now: t0.addingTimeInterval(100)), [])
  }

  func testDelayIsClampedToTheSettingRange() {
    XCTAssertEqual(BroadcastDelay<Int>(seconds: -5).seconds, 0)
    XCTAssertEqual(BroadcastDelay<Int>(seconds: 500).seconds, BroadcastDelay<Int>.maxSeconds)
  }
}
