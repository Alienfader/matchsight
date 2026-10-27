import Foundation

/// What the app is following and why — the input FollowPolicy decides from.
public struct FollowState: Sendable, Equatable {
  public var fixtureId: Int?
  /// The user tapped this match; auto-follow leaves it alone until it ends.
  public var isManual: Bool
  /// First time the followed match was seen finished.
  public var finishedAt: Date?
  /// Fixtures the user unfollowed; auto-follow never picks them again.
  public var suppressed: Set<Int>

  public init(fixtureId: Int? = nil, isManual: Bool = false,
              finishedAt: Date? = nil, suppressed: Set<Int> = []) {
    self.fixtureId = fixtureId
    self.isManual = isManual
    self.finishedAt = finishedAt
    self.suppressed = suppressed
  }

  /// Records the first time the followed match is seen over (any terminal
  /// status, not only full time), which starts the hold before moving on.
  public mutating func noteFollowedStatus(_ status: MatchStatus, fixtureId: Int, now: Date) {
    guard fixtureId == self.fixtureId, finishedAt == nil, status.isOver else { return }
    finishedAt = now
  }
}

public enum FollowDecision: Sendable, Equatable {
  case keep
  case follow(Int)
}

/// Auto-follow for favourite teams. Predictable above all: a followed match
/// that hasn't finished is never swapped (even if a poll drops it from the
/// list), a manual follow wins until its match ends, and the final score
/// stays up for `fullTimeHold` before another favourite's match takes over.
public enum FollowPolicy {
  public static let fullTimeHold: TimeInterval = 120
  public static let preKickoffWindow: TimeInterval = 300

  public static func decide(fixtures: [Fixture], favourites: Set<Int>,
                            state: FollowState, now: Date) -> FollowDecision {
    if state.fixtureId != nil {
      guard let finishedAt = state.finishedAt else { return .keep }
      guard now.timeIntervalSince(finishedAt) >= fullTimeHold else { return .keep }
    }
    let candidates = fixtures.filter { f in
      guard favourites.contains(f.home.id) || favourites.contains(f.away.id),
            !state.suppressed.contains(f.id), f.id != state.fixtureId else { return false }
      if f.status.isLive { return true }
      return f.status == .notStarted && f.kickoff.timeIntervalSince(now) <= preKickoffWindow
    }
    let best = candidates.min { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }
    return best.map { .follow($0.id) } ?? .keep
  }
}
