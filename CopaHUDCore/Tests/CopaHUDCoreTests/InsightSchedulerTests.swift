import XCTest
@testable import CopaHUDCore

/// The refresh policy is what keeps model calls rare: unchanged match data
/// never re-asks, changed data waits out a minimum interval, and a stale
/// insight is refreshed after maxAge. The cache serves repeat phone asks.
final class InsightSchedulerTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

  func testFirstRequestAllowed() {
    XCTAssertTrue(InsightScheduler().shouldAutoRequest(fingerprint: "a", now: t0))
  }

  func testSameFingerprintDoesNotRepeat() {
    var s = InsightScheduler()
    s.didRequest(fingerprint: "a", now: t0)
    XCTAssertFalse(s.shouldAutoRequest(fingerprint: "a", now: t0.addingTimeInterval(60)))
  }

  func testSameFingerprintRefreshesAfterMaxAge() {
    var s = InsightScheduler()
    s.didRequest(fingerprint: "a", now: t0)
    XCTAssertTrue(s.shouldAutoRequest(fingerprint: "a", now: t0.addingTimeInterval(600)))
  }

  func testChangedFingerprintWaitsMinInterval() {
    var s = InsightScheduler()
    s.didRequest(fingerprint: "a", now: t0)
    XCTAssertFalse(s.shouldAutoRequest(fingerprint: "b", now: t0.addingTimeInterval(10)))
    XCTAssertTrue(s.shouldAutoRequest(fingerprint: "b", now: t0.addingTimeInterval(30)))
  }

  func testResetAllowsImmediateRequest() {
    var s = InsightScheduler()
    s.didRequest(fingerprint: "a", now: t0)
    s.reset()
    XCTAssertTrue(s.shouldAutoRequest(fingerprint: "a", now: t0))
  }

  func testFailureAllowsRetryAfterMinIntervalWithSameData() {
    var s = InsightScheduler()
    s.didRequest(fingerprint: "a", now: t0)
    s.didFail()
    XCTAssertFalse(s.shouldAutoRequest(fingerprint: "a", now: t0.addingTimeInterval(10)))
    XCTAssertTrue(s.shouldAutoRequest(fingerprint: "a", now: t0.addingTimeInterval(30)))
  }

  private func insight(_ fingerprint: String, _ title: String = "T") -> MatchInsight {
    MatchInsight(title: title, body: "B", basis: .observed, factIds: ["F1"],
                 source: .model, fingerprint: fingerprint)
  }

  func testCacheHitAndMissByQuestion() {
    var c = InsightCache()
    c.store(insight("a"), question: .formation)
    XCTAssertEqual(c.insight(fingerprint: "a", question: .formation), insight("a"))
    XCTAssertNil(c.insight(fingerprint: "a", question: .matchStory))
    XCTAssertNil(c.insight(fingerprint: "b", question: .formation))
  }

  func testCacheEvictsOldest() {
    var c = InsightCache(capacity: 2)
    c.store(insight("a"), question: .formation)
    c.store(insight("b"), question: .formation)
    c.store(insight("c"), question: .formation)
    XCTAssertNil(c.insight(fingerprint: "a", question: .formation))
    XCTAssertNotNil(c.insight(fingerprint: "b", question: .formation))
    XCTAssertNotNil(c.insight(fingerprint: "c", question: .formation))
  }

  func testCacheRemoveAll() {
    var c = InsightCache()
    c.store(insight("a"), question: .formation)
    c.removeAll()
    XCTAssertNil(c.insight(fingerprint: "a", question: .formation))
  }
}
