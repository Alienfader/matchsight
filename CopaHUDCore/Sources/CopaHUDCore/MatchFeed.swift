import Foundation

/// The data seam from the design spec. ALL match data flows through this —
/// a server-assisted feed can slot in later without touching the UI.
public protocol MatchFeed: Sendable {
  func todaysFixtures() async throws -> [Fixture]
  /// Score, clock, status for one match.
  func liveSnapshot(fixtureId: Int) async throws -> MatchSnapshot
  /// Goals/cards/subs/VAR with synthesized stable ids (see MatchEvent docs).
  func events(fixtureId: Int) async throws -> [MatchEvent]
  func lineups(fixtureId: Int) async throws -> [Lineup]
  /// Snapshots of every other in-progress match.
  func otherLive() async throws -> [MatchSnapshot]
  /// Match statistics for the stats deck page. Best-effort: nil when the
  /// feed has none. Default implementation returns nil so custom feeds
  /// remain source-compatible.
  func stats(fixtureId: Int) async throws -> MatchStats?
  /// Per-player counters keyed by player id, for the glasses' player cards.
  /// Best-effort: empty when the feed has none (default implementation).
  func playerStats(fixtureId: Int) async throws -> [Int: PlayerStats]
  /// Pre-match win/draw/win percentages. Best-effort: nil when unavailable.
  func prediction(fixtureId: Int) async throws -> WinProbability?
  /// The next fixtures of these teams, any competition, by kickoff (the
  /// phone's Coming up list). Best-effort: empty by default.
  func upcomingFixtures(teamIds: [Int]) async throws -> [Fixture]
}

public extension MatchFeed {
  func stats(fixtureId: Int) async throws -> MatchStats? { nil }
  func playerStats(fixtureId: Int) async throws -> [Int: PlayerStats] { [:] }
  func prediction(fixtureId: Int) async throws -> WinProbability? { nil }
  func upcomingFixtures(teamIds: [Int]) async throws -> [Fixture] { [] }
}
