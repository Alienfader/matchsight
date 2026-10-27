import Foundation

// Pure value type, Foundation-only, no Date()/clock reads — time is irrelevant
// here. VAR detail strings are mapped by VarOutcome.init(detail:) in Engine/.

/// Pure state machine: consumes feed snapshots/events, diffs against prior
/// state, emits typed MatchMoments. Never re-fires a moment (dedup by stable
/// event id); detects VAR goal-overturns by goals vanishing from the feed.
public struct MatchEngine: Sendable {
  public init() {}

  // MARK: - Per-fixture state

  /// Bookkeeping for the single followed match (keyed by fixtureId so the user
  /// can switch which match they follow without leaking state).
  private struct FollowedState: Sendable {
    /// Every event id we've already turned into (or deliberately swallowed).
    var seen: Set<String> = []
    /// Goal-scoring events currently counted toward the score, kept whole so a
    /// vanish can be announced with the right minute.
    var countedGoals: [String: MatchEvent] = [:]
    /// Score implied by everything counted so far; the baseline for the next
    /// poll's reconstruction. Always realigned to the snapshot at poll end.
    var runningScore = ScoreLine(home: 0, away: 0)
    var prevStatus: MatchStatus?
    var fullTimeEmitted = false
    var hasIngested = false
  }

  private var followed: [Int: FollowedState] = [:]
  /// Last-known score per OTHER live fixture, for goal-increase detection.
  private var others: [Int: ScoreLine] = [:]

  // MARK: - Followed match

  /// Ingest a poll result for the FOLLOWED match. Returns new moments in
  /// chronological order. Re-polling the same data returns [].
  public mutating func ingestFollowed(snapshot: MatchSnapshot,
                                      events: [MatchEvent]) -> [MatchMoment] {
    var st = followed[snapshot.fixtureId] ?? FollowedState()
    defer { followed[snapshot.fixtureId] = st }

    let firstIngest = !st.hasIngested
    st.hasIngested = true

    // Mid-match first ingest: the user followed after kickoff. Seed silently so
    // history doesn't replay as takeovers. Status transitions still apply later.
    if firstIngest && snapshot.status.isLive && !events.isEmpty {
      for e in events {
        st.seen.insert(e.id)
        if case .goal(let d) = e.kind, d != .missedPenalty {
          st.countedGoals[e.id] = e
        }
      }
      st.runningScore = snapshot.score
      st.prevStatus = snapshot.status
      return []
    }

    var out: [MatchMoment] = []
    let fixtureId = snapshot.fixtureId
    let currentIds = Set(events.map(\.id))

    // New events only, in chronological order (minute, then extra minute).
    let newEvents = events
      .filter { !st.seen.contains($0.id) }
      .sorted { ($0.minute, $0.extraMinute ?? 0) < ($1.minute, $1.extraMinute ?? 0) }

    // Count explicit VAR overturn events this poll so a coincident goal-vanish
    // can collapse into them rather than double-firing.
    let explicitOverturns = newEvents.reduce(into: 0) { acc, e in
      if case .varDecision(let detail) = e.kind, VarOutcome(detail: detail) == .goalOverturned {
        acc += 1
      }
    }

    var running = st.runningScore
    var lastGoalIndex: Int?

    for e in newEvents {
      st.seen.insert(e.id)
      switch e.kind {
      case .goal(let detail):
        guard detail != .missedPenalty else { continue }  // seen, but no moment
        if scoresForHome(e, snapshot: snapshot) { running.home += 1 } else { running.away += 1 }
        st.countedGoals[e.id] = e
        out.append(MatchMoment(fixtureId: fixtureId,
                               kind: .goal(scorer: e.player, assist: e.assist, detail: detail),
                               score: running, minute: e.minute, playerId: e.playerId))
        lastGoalIndex = out.count - 1

      case .card(let detail):
        guard detail == .red else { continue }  // yellow: no moment
        out.append(MatchMoment(fixtureId: fixtureId,
                               kind: .redCard(player: e.player, team: e.team),
                               score: running, minute: e.minute, playerId: e.playerId))

      case .substitution, .unknown:
        continue  // recorded as seen, no moment

      case .varDecision(let detail):
        switch VarOutcome(detail: detail) {
        case .penaltyConfirmed:
          out.append(MatchMoment(fixtureId: fixtureId,
                                 kind: .penaltyAwarded(team: e.team),
                                 score: running, minute: e.minute))
        case .goalOverturned:
          out.append(MatchMoment(fixtureId: fixtureId,
                                 kind: .varDecision(.goalOverturned),
                                 score: snapshot.score, minute: e.minute))
        case let outcome:
          out.append(MatchMoment(fixtureId: fixtureId,
                                 kind: .varDecision(outcome),
                                 score: running, minute: e.minute))
        }
      }
    }

    // Feed lag: the goal sequence didn't reach the snapshot score. Trust the
    // snapshot for the LAST goal moment.
    if let i = lastGoalIndex, running != snapshot.score {
      out[i] = MatchMoment(fixtureId: fixtureId, kind: out[i].kind,
                           score: snapshot.score, minute: out[i].minute)
    }

    // VAR goal-vanish: a counted goal absent from the feed with the score now
    // lower → announce the overturn (the panel never silently rewrites history).
    let priorTotal = st.runningScore.home + st.runningScore.away
    let snapTotal = snapshot.score.home + snapshot.score.away
    if snapTotal < priorTotal {
      let vanished = st.countedGoals.values
        .filter { !currentIds.contains($0.id) }
        .sorted { ($0.minute, $0.extraMinute ?? 0) < ($1.minute, $1.extraMinute ?? 0) }
      for g in vanished {
        st.countedGoals[g.id] = nil
        st.seen.remove(g.id)
      }
      // Collapse with any explicit overturn events already emitted above.
      let synthetic = max(0, vanished.count - explicitOverturns)
      for g in vanished.prefix(synthetic) {
        out.append(MatchMoment(fixtureId: fixtureId,
                               kind: .varDecision(.goalOverturned),
                               score: snapshot.score, minute: g.minute))
      }
    }

    // Status transitions (compared against the previous snapshot's status).
    if let prev = st.prevStatus, prev != .halfTime, snapshot.status == .halfTime {
      out.append(MatchMoment(fixtureId: fixtureId, kind: .halfTime,
                             score: snapshot.score, minute: snapshot.elapsedMinutes))
    }
    if snapshot.status.isFinished && !st.fullTimeEmitted {
      st.fullTimeEmitted = true
      out.append(MatchMoment(fixtureId: fixtureId, kind: .fullTime,
                             score: snapshot.score, minute: snapshot.elapsedMinutes))
    }

    st.prevStatus = snapshot.status
    st.runningScore = snapshot.score
    return out
  }

  /// Which side a goal credits: own goals credit the opponent.
  private func scoresForHome(_ e: MatchEvent, snapshot: MatchSnapshot) -> Bool {
    let isOwnGoal: Bool
    if case .goal(.ownGoal) = e.kind { isOwnGoal = true } else { isOwnGoal = false }
    let eventTeamIsHome = e.team.id == snapshot.home.id
    return isOwnGoal ? !eventTeamIsHome : eventTeamIsHome
  }

  // MARK: - Other matches

  /// Ingest snapshots of all OTHER live matches. Returns one otherMatchGoal
  /// moment per goal scored since last seen; decreases update silently.
  public mutating func ingestOthers(_ snapshots: [MatchSnapshot]) -> [MatchMoment] {
    var out: [MatchMoment] = []
    for s in snapshots {
      if let last = others[s.fixtureId] {
        let scored = max(0, s.score.home - last.home) + max(0, s.score.away - last.away)
        for _ in 0..<scored {
          out.append(MatchMoment(fixtureId: s.fixtureId,
                                 kind: .otherMatchGoal(snapshot: s, scorer: nil),
                                 score: s.score, minute: s.elapsedMinutes))
        }
      }
      // First sighting just records; every poll refreshes the baseline.
      others[s.fixtureId] = s.score
    }
    return out
  }

  // MARK: - Reset

  /// Forget all state for a fixture (e.g. user unfollowed).
  public mutating func reset(fixtureId: Int) {
    followed[fixtureId] = nil
    others[fixtureId] = nil
  }
}

/// Poll cadence policy from the spec: followed 15s · others 60s · half-time
/// 60s · zero polling outside scheduled match windows.
public enum PollPlanner {
  /// Interval for polling the followed match, or nil when it shouldn't be polled.
  public static func followedInterval(status: MatchStatus) -> TimeInterval? {
    guard status.isLive else { return nil }
    return status == .halfTime ? 60 : 15
  }

  /// Interval for polling other live matches, or nil when none are live.
  public static func othersInterval(anyLive: Bool) -> TimeInterval? {
    anyLive ? 60 : nil
  }

  /// When polling should next wake up given today's fixtures (2 minutes
  /// before the earliest kickoff still ahead), or nil when nothing is coming.
  public static func nextPollWindow(fixtures: [Fixture], now: Date) -> Date? {
    fixtures
      .filter { !$0.status.isFinished }
      .map { $0.kickoff.addingTimeInterval(-120) }
      .filter { $0 > now }
      .min()
  }
}
