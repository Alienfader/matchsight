import XCTest
@testable import CopaHUDCore

/// Sync with TV: the feed gives whole minutes, so the live clock is pinned to
/// the moment a minute ticks over; the fan taps when the TV clock reaches a
/// whole minute, and the difference is the TV delay.
final class TVSyncTests: XCTestCase {
  let t0 = Date(timeIntervalSince1970: 1_780_000_000)
  private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

  func testNoClockUntilAMinuteTicksOver() {
    var clock = LiveMatchClock()
    clock.observe(minute: 52, status: .secondHalf, at: at(0))
    clock.observe(minute: 52, status: .secondHalf, at: at(15))
    XCTAssertNil(clock.seconds(at: at(20)))
  }

  func testTheTickIsPlacedBetweenTheTwoPolls() {
    var clock = LiveMatchClock()
    clock.observe(minute: 52, status: .secondHalf, at: at(0))
    clock.observe(minute: 53, status: .secondHalf, at: at(16))
    // Minute 53 began about 8 s in, when a TV clock read 52:00.
    XCTAssertEqual(clock.seconds(at: at(8)) ?? -1, 52 * 60, accuracy: 0.001)
    XCTAssertEqual(clock.seconds(at: at(38)) ?? -1, 52 * 60 + 30, accuracy: 0.001)
    // Later polls in the same minute keep the anchor.
    clock.observe(minute: 53, status: .secondHalf, at: at(31))
    XCTAssertEqual(clock.seconds(at: at(38)) ?? -1, 52 * 60 + 30, accuracy: 0.001)
  }

  func testAJumpOrAPauseDropsTheClock() {
    var clock = LiveMatchClock()
    clock.observe(minute: 52, status: .secondHalf, at: at(0))
    clock.observe(minute: 53, status: .secondHalf, at: at(16))
    clock.observe(minute: 45, status: .halfTime, at: at(30))
    XCTAssertNil(clock.seconds(at: at(31)), "no clock at half-time")
    var jumpy = LiveMatchClock()
    jumpy.observe(minute: 50, status: .secondHalf, at: at(0))
    jumpy.observe(minute: 53, status: .secondHalf, at: at(15))
    XCTAssertNil(jumpy.seconds(at: at(16)), "a skipped minute can't place the tick")
  }

  func testStoppageTimeHasNoClock() {
    // The feed holds 45 / 90 through stoppage time, so no tick to place.
    var clock = LiveMatchClock()
    clock.observe(minute: 89, status: .secondHalf, at: at(0))
    clock.observe(minute: 90, status: .secondHalf, at: at(16))
    XCTAssertNil(clock.seconds(at: at(20)))
  }

  func testAStaleAnchorExpires() {
    var clock = LiveMatchClock()
    clock.observe(minute: 52, status: .secondHalf, at: at(0))
    clock.observe(minute: 53, status: .secondHalf, at: at(16))
    XCTAssertNil(clock.seconds(at: at(16 + LiveMatchClock.maxAge + 1)))
  }

  // MARK: the tap

  func testTheDelayIsHowFarTheTVIsBehind() {
    XCTAssertEqual(TVSync.delay(liveSeconds: 52 * 60 + 150, tvMinute: 52), .delay(150))
    XCTAssertEqual(TVSync.delay(liveSeconds: 52 * 60 + 31, tvMinute: 52), .delay(31))
  }

  func testATVCloseToLiveNeedsNoDelay() {
    // The feed's clock runs from kickoff, but its goals arrive after the TV
    // shows them (2026-10-28: sync said 13 s, the goal came later anyway).
    // Within 30 s of the clock, any delay only makes alerts later.
    XCTAssertEqual(TVSync.delay(liveSeconds: 10 * 60 + 13, tvMinute: 10), .delay(0))
    XCTAssertEqual(TVSync.delay(liveSeconds: 52 * 60 + 29, tvMinute: 52), .delay(0))
    // A tap a few seconds early is still "live", not "TV ahead".
    XCTAssertEqual(TVSync.delay(liveSeconds: 52 * 60 - 10, tvMinute: 52), .delay(0))
  }

  func testATVAheadOfTheDataOrTooFarBehindIsRejected() {
    XCTAssertEqual(TVSync.delay(liveSeconds: 52 * 60, tvMinute: 53), .tvAhead)
    XCTAssertEqual(TVSync.delay(liveSeconds: 60 * 60, tvMinute: 50), .tooFarBehind)
  }

  func testTheSuggestedMinuteIsTheTVsNextWholeMinute() {
    // Live 52:30 with a 90 s delay: the TV shows 51:00, so 52:00 is next.
    XCTAssertEqual(TVSync.suggestedMinute(liveSeconds: 52 * 60 + 30, currentDelay: 90), 52)
    XCTAssertEqual(TVSync.suggestedMinute(liveSeconds: 52 * 60 + 30, currentDelay: 0), 53)
  }
}
