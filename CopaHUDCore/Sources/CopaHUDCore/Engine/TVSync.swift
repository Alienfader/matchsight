import Foundation

/// The live match clock to the second, from a feed that only gives whole
/// minutes: the moment the minute ticks over (between two polls, so within
/// half a poll interval) pins it. Assumes the usual football count: minute 53
/// starts when a TV clock reads 52:00.
public struct LiveMatchClock: Sendable {
  /// An anchor older than this is not trusted (the app may have stopped polling).
  public static let maxAge: TimeInterval = 15 * 60

  private var last: (minute: Int, status: MatchStatus, at: Date)?
  /// When `minute` began.
  private var anchor: (minute: Int, at: Date)?

  public init() {}

  public mutating func observe(minute: Int?, status: MatchStatus, at now: Date) {
    defer { last = minute.map { ($0, status, now) } }
    guard let minute, status == .firstHalf || status == .secondHalf || status == .extraTime else {
      anchor = nil; return
    }
    // The feed holds 45 / 90 / 120 through stoppage time: no tick to trust.
    if [45, 90, 105, 120].contains(minute) { anchor = nil; return }
    guard let last, last.status == status else { anchor = nil; return }
    if minute == last.minute + 1 {
      anchor = (minute, last.at.addingTimeInterval(now.timeIntervalSince(last.at) / 2))
    } else if minute != last.minute {
      anchor = nil
    }
  }

  /// Seconds on a TV-style match clock right now, or nil without a fresh tick.
  public func seconds(at now: Date) -> TimeInterval? {
    guard let anchor, now.timeIntervalSince(anchor.at) <= Self.maxAge else { return nil }
    return Double(anchor.minute - 1) * 60 + now.timeIntervalSince(anchor.at)
  }
}

/// Sync with TV: the fan taps the moment the TV clock reaches `tvMinute`:00;
/// how far the live clock is past that is the TV delay.
public enum TVSync {
  public enum Outcome: Sendable, Equatable {
    case delay(TimeInterval)
    /// The TV can't be ahead of the live data: a later minute was picked.
    case tvAhead
    /// More than the TV delay allows: an earlier minute was picked.
    case tooFarBehind
  }

  /// Within this of the feed's clock the TV counts as live. The clock runs
  /// from kickoff, but goals reach the feed after the TV shows them, so a
  /// small delay would only make goal alerts later (seen 2026-10-28).
  public static let liveWindow: TimeInterval = 30
  /// A tap this early still counts as live, not as a TV ahead of the data.
  public static let tapSlack: TimeInterval = 15

  public static func delay(liveSeconds: TimeInterval, tvMinute: Int) -> Outcome {
    let behind = liveSeconds - Double(tvMinute) * 60
    if behind < -tapSlack { return .tvAhead }
    if behind < liveWindow { return .delay(0) }
    if behind > BroadcastDelay<Int>.maxSeconds { return .tooFarBehind }
    return .delay(behind.rounded())
  }

  /// The next whole minute the TV will show, given the delay set now.
  public static func suggestedMinute(liveSeconds: TimeInterval, currentDelay: TimeInterval) -> Int {
    Int(((liveSeconds - currentDelay) / 60).rounded(.down)) + 1
  }
}
