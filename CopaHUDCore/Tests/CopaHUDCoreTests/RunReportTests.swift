import XCTest
@testable import CopaHUDCore

final class RunReportTests: XCTestCase {
  // Lines as `dbg()` prints them, captured through `script` (so \r\n endings),
  // with unrelated device-console noise mixed in.
  let log = [
    "Launched application with com.alienfader.CopaHUD bundle identifier.",
    "[CopaHUD] session started; adding display",
    "[CopaHUD] session state → started",
    "[CopaHUD] display state → started",
    "[CopaHUD] follow: auto → 1001",
    "[CopaHUD] audit: ok followed=1001",
    "[CopaHUD] poll 1001: 1H 12' 0-0, 3 events",
    "[CopaHUD] poll 1001: 1H 13' 1-0, 4 events",
    "[CopaHUD] render error: Timed out waiting for display response",
    "[CopaHUD] input → back (system gesture)",
    "[CopaHUD] session error: sessionEnded",
    "[CopaHUD] session state → stopping",
    "[CopaHUD] session state → stopped",
    "[CopaHUD] display state → stopped",
    "[CopaHUD] session state → started",
    "[CopaHUD] audit: WRONG followed=2002 not-a-favourite(2002)",
    "[CopaHUD] audit: WRONG followed=2002 not-a-favourite(2002)",
    "[CopaHUD] audit: ok followed=1001",
    "[CopaHUD] audit: WRONG followed=1001 shown-mismatch(1001≠7)",
    "[CopaHUD] render error: some other failure",
    "[CopaHUD] session error: sessionEnded",
  ].joined(separator: "\r\n")

  func testCountsLifecycleEvents() {
    let r = RunReport.parse(log)
    XCTAssertEqual(r.sessionStarts, 2)
    XCTAssertEqual(r.disconnects, 1)          // `stopped`, not `stopping`
    XCTAssertEqual(r.displayStops, 1)
    XCTAssertEqual(r.backGestures, 1)
    XCTAssertEqual(r.sessionErrors, ["sessionEnded": 2])
  }

  func testCountsRenderErrorsAndTimeouts() {
    let r = RunReport.parse(log)
    XCTAssertEqual(r.renderErrors, 2)
    XCTAssertEqual(r.renderTimeouts, 1)
  }

  func testCountsPollsAndFollowSwitches() {
    let r = RunReport.parse(log)
    XCTAssertEqual(r.polls, 2)
    XCTAssertEqual(r.followSwitches, 1)
  }

  func testWrongMatchEventsCountRunsNotChecks() {
    // Two consecutive WRONG checks are one event; ok → WRONG starts another.
    let r = RunReport.parse(log)
    XCTAssertEqual(r.auditChecks, 5)
    XCTAssertEqual(r.wrongMatchChecks, 3)
    XCTAssertEqual(r.wrongMatchEvents, 2)
    XCTAssertEqual(r.wrongMatchReasons, ["not-a-favourite(2002)", "shown-mismatch(1001≠7)"])
  }

  func testEmptyLogIsAllZeroAndSaysNoAudit() {
    let r = RunReport.parse("nothing from the app here\n")
    XCTAssertEqual(r.disconnects, 0)
    XCTAssertEqual(r.auditChecks, 0)
    XCTAssertTrue(r.summary.contains("No audit lines"))
  }

  func testSummaryLeadsWithTheAntiGoals() {
    let lines = RunReport.parse(log).summary.split(separator: "\n").map(String.init)
    XCTAssertEqual(lines.first, "Anti-goals: 1 disconnect, 2 wrong-match events")
    XCTAssertTrue(lines.contains("Session errors: sessionEnded ×2"))
    XCTAssertTrue(lines.contains("Back gestures (exit the app): 1"))
  }
}
