import Foundation

/// One stats reading and the match minute it was taken at.
public struct StatsSample: Sendable, Equatable {
  public var minute: Int
  public var stats: MatchStats

  public init(minute: Int, stats: MatchStats) {
    self.minute = minute
    self.stats = stats
  }
}

/// Who has been pushing lately, from the change in shots, shots on target
/// and corners over a window of match minutes. The feed gives counts only
/// (no positions, no xG per minute), so this is a rough read.
public struct Momentum: Sendable, Equatable {
  /// Weighted attacking actions in the window: on target ×3, other shots
  /// and corners ×1.
  public var home: Int
  public var away: Int
  /// -1 (all away) … 0 (level) … 1 (all home).
  public var balance: Double {
    let total = home + away
    return total == 0 ? 0 : Double(home - away) / Double(total)
  }

  /// Shortest history that counts as a trend.
  static let minimumSpan = 5

  /// Compares the latest sample with the one at (or just before) `window`
  /// minutes earlier. Nil without enough history or counts.
  public static func reading(_ history: [StatsSample], window: Int = 10) -> Momentum? {
    guard let last = history.max(by: { $0.minute < $1.minute }) else { return nil }
    let candidates = history.filter { $0.minute <= last.minute - minimumSpan }
    guard let base = candidates.filter({ $0.minute >= last.minute - window }).min(by: { $0.minute < $1.minute })
            ?? candidates.max(by: { $0.minute < $1.minute }) else { return nil }
    guard let h = pressure(from: base.stats.home, to: last.stats.home),
          let a = pressure(from: base.stats.away, to: last.stats.away) else { return nil }
    return Momentum(home: h, away: a)
  }

  private static func pressure(from old: TeamStats, to new: TeamStats) -> Int? {
    guard let s0 = old.totalShots, let s1 = new.totalShots,
          let t0 = old.shotsOnGoal, let t1 = new.shotsOnGoal else { return nil }
    let onTarget = max(0, t1 - t0)
    let offTarget = max(0, (s1 - s0) - onTarget)
    let corners = max(0, (new.corners ?? 0) - (old.corners ?? 0))
    return onTarget * 3 + offTarget + corners
  }
}
