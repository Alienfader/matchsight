import XCTest
@testable import CopaHUDCore

/// Momentum: who has been pushing over the last ten minutes, from the
/// changes in shots, shots on target and corners. Counts only, so it's a
/// rough read, and labelled as such on the glasses.
final class MomentumTests: XCTestCase {
  private func sample(_ minute: Int, shots: (Int, Int), onTarget: (Int, Int), corners: (Int, Int)) -> StatsSample {
    StatsSample(minute: minute, stats: MatchStats(
      home: TeamStats(totalShots: shots.0, shotsOnGoal: onTarget.0, corners: corners.0),
      away: TeamStats(totalShots: shots.1, shotsOnGoal: onTarget.1, corners: corners.1)))
  }

  func testTheHomeSidePushingLeansHome() {
    let history = [sample(50, shots: (5, 5), onTarget: (2, 2), corners: (2, 2)),
                   sample(60, shots: (9, 5), onTarget: (4, 2), corners: (4, 2))]
    let m = Momentum.reading(history, window: 10)
    // Home: 2 on target × 3 + 2 off target + 2 corners = 10; away 0.
    XCTAssertEqual(m?.home, 10)
    XCTAssertEqual(m?.away, 0)
    XCTAssertEqual(m?.balance ?? 0, 1, accuracy: 0.001)
  }

  func testTheWindowStartsTenMinutesBack() {
    let history = [sample(30, shots: (0, 0), onTarget: (0, 0), corners: (0, 0)),
                   sample(50, shots: (5, 5), onTarget: (2, 2), corners: (2, 2)),
                   sample(60, shots: (6, 7), onTarget: (2, 3), corners: (2, 3))]
    let m = Momentum.reading(history, window: 10)
    // Since 50': home +1 off target; away +1 on target (3) +1 off (1) +1 corner.
    XCTAssertEqual(m?.home, 1)
    XCTAssertEqual(m?.away, 5)
    XCTAssertEqual(m?.balance ?? 0, (1 - 5) / 6.0, accuracy: 0.001)
  }

  func testQuietSpellsAndTooLittleDataGiveNoReading() {
    let flat = [sample(50, shots: (5, 5), onTarget: (2, 2), corners: (2, 2)),
                sample(60, shots: (5, 5), onTarget: (2, 2), corners: (2, 2))]
    XCTAssertEqual(Momentum.reading(flat, window: 10)?.balance, 0, "level, not missing")
    XCTAssertNil(Momentum.reading([sample(60, shots: (5, 5), onTarget: (2, 2), corners: (2, 2))], window: 10))
    // Less than five minutes of history isn't a trend yet.
    XCTAssertNil(Momentum.reading([sample(57, shots: (0, 0), onTarget: (0, 0), corners: (0, 0)),
                                   sample(60, shots: (3, 0), onTarget: (1, 0), corners: (0, 0))], window: 10))
  }

  func testMissingCountsCountAsNothing() {
    let history = [StatsSample(minute: 50, stats: MatchStats(home: TeamStats(), away: TeamStats())),
                   sample(60, shots: (2, 0), onTarget: (1, 0), corners: (0, 0))]
    XCTAssertNil(Momentum.reading(history, window: 10), "no baseline counts, no trend")
  }
}
