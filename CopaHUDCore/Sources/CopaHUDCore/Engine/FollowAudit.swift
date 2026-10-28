import Foundation

/// Reliability check for the founder's anti-goal "showing the wrong match".
/// Runs after each FollowPolicy decision and judges the outcome against the
/// same rules, independently: a finding means the policy (or the state
/// around it) let the glasses show something the fan wouldn't expect.
/// A manual follow is the fan's choice and is only checked for stale data.
public enum FollowAudit {
  public enum Finding: Sendable, Equatable {
    /// A favourite's match is live and nothing is followed.
    case notFollowing(live: Int)
    /// Auto-follow picked a match neither of whose teams is a favourite.
    case notAFavourite(followed: Int)
    /// Auto-follow is on a later kickoff while an earlier favourite match is live.
    case laterKickoff(followed: Int, earlier: Int)
    /// The glasses show data from a different fixture than the followed one.
    case shownMismatch(followed: Int, shown: Int)
  }

  public static func check(fixtures: [Fixture], favourites: Set<Int>, state: FollowState,
                           shownFixtureId: Int?, now: Date) -> [Finding] {
    func isFavourite(_ f: Fixture) -> Bool {
      favourites.contains(f.home.id) || favourites.contains(f.away.id)
    }
    let liveFavourites = fixtures.filter {
      $0.status.isLive && isFavourite($0) && !state.suppressed.contains($0.id)
    }
    var findings: [Finding] = []

    guard let followed = state.fixtureId else {
      if let first = liveFavourites.min(by: { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }) {
        findings.append(.notFollowing(live: first.id))
      }
      return findings
    }

    if !state.isManual, let fixture = fixtures.first(where: { $0.id == followed }) {
      let earlier = liveFavourites.filter { $0.id != followed && $0.kickoff < fixture.kickoff }
      if !isFavourite(fixture) {
        findings.append(.notAFavourite(followed: followed))
      } else if let first = earlier.min(by: { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }) {
        findings.append(.laterKickoff(followed: followed, earlier: first.id))
      }
    }

    if let shown = shownFixtureId, shown != followed {
      findings.append(.shownMismatch(followed: followed, shown: shown))
    }
    return findings
  }

  /// One console line per check; `RunReport` parses these.
  public static func logLine(_ findings: [Finding], followed: Int?) -> String {
    let id = followed.map(String.init) ?? "none"
    guard !findings.isEmpty else { return "audit: ok followed=\(id)" }
    return "audit: WRONG followed=\(id) " + findings.map(label).joined(separator: " ")
  }

  static func label(_ finding: Finding) -> String {
    switch finding {
    case .notFollowing(let live): return "not-following(\(live))"
    case .notAFavourite(let followed): return "not-a-favourite(\(followed))"
    case .laterKickoff(let followed, let earlier): return "later-kickoff(\(followed)>\(earlier))"
    case .shownMismatch(let followed, let shown): return "shown-mismatch(\(followed)≠\(shown))"
    }
  }
}
