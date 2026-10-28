import Foundation

/// A scripted full-match replay used for development and on-glasses rehearsal.
///
/// The script is a timeline of keyframes (state at N seconds from kickoff). The
/// feed reports the latest keyframe whose `at` has been reached on a scaled
/// clock — `elapsed = (now() - startedAt) * speed` — so a 90-minute match plays
/// back in 90 seconds at `speed = 60`. Everything is deterministic when `now`
/// is injected.
public struct MatchScript: Codable, Sendable, Equatable {

  public struct ScriptTeam: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    /// Crest URL (optional; older scripts have none).
    public let logo: String?
    public init(id: Int, name: String, logo: String? = nil) {
      self.id = id; self.name = name; self.logo = logo
    }

    var team: Team { Team(id: id, name: name, logoURL: logo.flatMap(URL.init(string:))) }
  }

  public struct ScriptFixture: Codable, Sendable, Equatable {
    public let id: Int
    public let home: ScriptTeam
    public let away: ScriptTeam
    public let groupLabel: String?
    public let venue: String?
    public init(id: Int, home: ScriptTeam, away: ScriptTeam,
                groupLabel: String?, venue: String?) {
      self.id = id; self.home = home; self.away = away
      self.groupLabel = groupLabel; self.venue = venue
    }
  }

  public struct ScriptScore: Codable, Sendable, Equatable {
    public let home: Int
    public let away: Int
    public init(home: Int, away: Int) { self.home = home; self.away = away }

    var scoreLine: ScoreLine { ScoreLine(home: home, away: away) }
  }

  /// A scripted event. Carries an optional `playerId` so the synthesized id
  /// follows the exact same rule the real feed uses.
  public struct ScriptEvent: Codable, Sendable, Equatable {
    public let minute: Int
    public let extraMinute: Int?
    public let teamId: Int
    public let teamName: String
    public let playerId: Int?
    public let player: String?
    public let assist: String?
    public let type: String
    public let detail: String

    public init(minute: Int, extraMinute: Int?, teamId: Int, teamName: String,
                playerId: Int?, player: String?, assist: String?,
                type: String, detail: String) {
      self.minute = minute; self.extraMinute = extraMinute
      self.teamId = teamId; self.teamName = teamName
      self.playerId = playerId; self.player = player; self.assist = assist
      self.type = type; self.detail = detail
    }

    func toEvent(fixtureId: Int) -> MatchEvent {
      MatchEvent(
        id: EventID.synthesize(fixtureId: fixtureId, minute: minute,
                               extraMinute: extraMinute, teamId: teamId,
                               rawType: type, rawDetail: detail, playerId: playerId),
        fixtureId: fixtureId,
        minute: minute,
        extraMinute: extraMinute,
        team: Team(id: teamId, name: teamName),
        player: player,
        playerId: playerId,
        assist: assist,
        kind: EventKindMapper.kind(type: type, detail: detail))
    }
  }

  public struct Keyframe: Codable, Sendable, Equatable {
    /// Seconds from kickoff at which this state becomes current.
    public let at: Double
    /// API-Football short status code, e.g. "1H", "HT", "2H", "FT".
    public let status: String
    public let elapsed: Int?
    public let score: ScriptScore
    /// Cumulative events present at this keyframe. A VAR overturn is modelled by
    /// a goal event present in earlier keyframes then ABSENT here.
    public let events: [ScriptEvent]

    public init(at: Double, status: String, elapsed: Int?,
                score: ScriptScore, events: [ScriptEvent]) {
      self.at = at; self.status = status; self.elapsed = elapsed
      self.score = score; self.events = events
    }
  }

  public struct ScriptPlayer: Codable, Sendable, Equatable {
    public let name: String
    public let number: Int?
    public let position: String?
    public let grid: String?
    public let playerId: Int?
    public init(name: String, number: Int?, position: String?, grid: String?,
                playerId: Int? = nil) {
      self.name = name; self.number = number
      self.position = position; self.grid = grid
      self.playerId = playerId
    }

    var lineupPlayer: LineupPlayer {
      LineupPlayer(name: name, number: number, position: position, grid: grid,
                   playerId: playerId)
    }
  }

  public struct ScriptLineup: Codable, Sendable, Equatable {
    public let teamId: Int
    public let teamName: String
    public let formation: String?
    public let startXI: [ScriptPlayer]
    public let coach: String?
    public init(teamId: Int, teamName: String, formation: String?,
                startXI: [ScriptPlayer], coach: String?) {
      self.teamId = teamId; self.teamName = teamName
      self.formation = formation; self.startXI = startXI; self.coach = coach
    }

    func toLineup(fixtureId: Int) -> Lineup {
      Lineup(fixtureId: fixtureId, team: Team(id: teamId, name: teamName),
             formation: formation, startXI: startXI.map(\.lineupPlayer), coach: coach)
    }
  }

  public let fixture: ScriptFixture
  public let keyframes: [MatchScript.Keyframe]
  public let lineups: [ScriptLineup]
  /// A second match running in parallel, for cross-match toast rehearsal.
  public let other: ScriptFixture
  public let otherKeyframes: [MatchScript.Keyframe]

  public init(fixture: ScriptFixture, keyframes: [MatchScript.Keyframe], lineups: [ScriptLineup],
              other: ScriptFixture, otherKeyframes: [MatchScript.Keyframe]) {
    self.fixture = fixture
    self.keyframes = keyframes
    self.lineups = lineups
    self.other = other
    self.otherKeyframes = otherKeyframes
  }

  /// Decode a script from JSON data.
  public static func load(from data: Data) throws -> MatchScript {
    try JSONDecoder().decode(MatchScript.self, from: data)
  }

  /// A no-op script with zero keyframes — used as a safe fallback when the
  /// bundled resource cannot be loaded (should never happen in a real install).
  public static let empty = MatchScript(
    fixture: ScriptFixture(id: 0, home: ScriptTeam(id: 0, name: "Home"),
                           away: ScriptTeam(id: 1, name: "Away"),
                           groupLabel: nil, venue: nil),
    keyframes: [],
    lineups: [],
    other: ScriptFixture(id: 1, home: ScriptTeam(id: 2, name: "A"),
                         away: ScriptTeam(id: 3, name: "B"),
                         groupLabel: nil, venue: nil),
    otherKeyframes: []
  )

  /// The BRA 3–2 ARG / FRA 2–0 GER demo script bundled with CopaHUDCore.
  public static func bundled() throws -> MatchScript {
    guard let url = Bundle.module.url(forResource: "mock-match-script", withExtension: "json"),
          let data = try? Data(contentsOf: url) else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    return try load(from: data)
  }
}

/// Replays a `MatchScript` through the `MatchFeed` seam.
public final class MockFeed: MatchFeed, @unchecked Sendable {
  private let script: MatchScript
  private let speed: Double
  private let now: @Sendable () -> Date

  /// The scripted main match's two teams. Demo-mode auto-follow uses these
  /// rather than every scripted team, so it never picks the side match.
  public var primaryTeamIds: Set<Int> { [script.fixture.home.id, script.fixture.away.id] }

  private let lock = NSLock()
  private var startedAt: Date?

  public init(script: MatchScript, speed: Double = 1.0,
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.script = script
    self.speed = speed
    self.now = now
  }

  /// Marks kickoff (t = 0). Before this, every endpoint reports pre-kickoff.
  public func start() {
    lock.lock()
    startedAt = now()
    lock.unlock()
  }

  // MARK: - Scaled clock

  /// Scaled seconds since kickoff, or nil before `start()`.
  private func elapsedSeconds() -> Double? {
    lock.lock()
    defer { lock.unlock() }
    guard let startedAt else { return nil }
    return now().timeIntervalSince(startedAt) * speed
  }

  private func kickoffDate() -> Date {
    lock.lock()
    defer { lock.unlock() }
    return startedAt ?? now()
  }

  /// The latest keyframe whose `at` has been reached, or nil before kickoff.
  private func currentKeyframe(_ frames: [MatchScript.Keyframe]) -> MatchScript.Keyframe? {
    guard let elapsed = elapsedSeconds() else { return nil }
    return frames.last { $0.at <= elapsed }
  }

  private func snapshot(for fixture: MatchScript.ScriptFixture,
                        frames: [MatchScript.Keyframe]) -> MatchSnapshot {
    let kickoff = kickoffDate()
    guard let frame = currentKeyframe(frames) else {
      // Pre-kickoff: honest 0-0, not started.
      return MatchSnapshot(
        fixtureId: fixture.id, home: fixture.home.team, away: fixture.away.team,
        score: ScoreLine(home: 0, away: 0), status: .notStarted,
        elapsedMinutes: nil, possessionHome: nil,
        groupLabel: fixture.groupLabel, kickoff: kickoff)
    }
    return MatchSnapshot(
      fixtureId: fixture.id, home: fixture.home.team, away: fixture.away.team,
      score: frame.score.scoreLine, status: MatchStatus(short: frame.status),
      elapsedMinutes: frame.elapsed, possessionHome: nil,
      groupLabel: fixture.groupLabel, kickoff: kickoff)
  }

  private func frames(for fixtureId: Int) -> (MatchScript.ScriptFixture, [MatchScript.Keyframe])? {
    if fixtureId == script.fixture.id { return (script.fixture, script.keyframes) }
    if fixtureId == script.other.id { return (script.other, script.otherKeyframes) }
    return nil
  }

  // MARK: - MatchFeed

  public func todaysFixtures() async throws -> [Fixture] {
    let kickoff = kickoffDate()
    return [script.fixture, script.other].map { fixture in
      let frames = fixture.id == script.fixture.id ? script.keyframes : script.otherKeyframes
      let status = currentKeyframe(frames).map { MatchStatus(short: $0.status) } ?? .notStarted
      return Fixture(id: fixture.id, kickoff: kickoff,
                     home: fixture.home.team, away: fixture.away.team,
                     groupLabel: fixture.groupLabel, competition: "\(fixture.groupLabel ?? "Scripted match") (demo)",
                     venue: fixture.venue, status: status)
    }
  }

  public func liveSnapshot(fixtureId: Int) async throws -> MatchSnapshot {
    guard let (fixture, frames) = frames(for: fixtureId) else {
      throw FeedError.decoding("unknown fixture \(fixtureId) in mock script")
    }
    return snapshot(for: fixture, frames: frames)
  }

  public func events(fixtureId: Int) async throws -> [MatchEvent] {
    guard let (_, frames) = frames(for: fixtureId) else {
      throw FeedError.decoding("unknown fixture \(fixtureId) in mock script")
    }
    guard let frame = currentKeyframe(frames) else { return [] }
    return frame.events.map { $0.toEvent(fixtureId: fixtureId) }
  }

  public func lineups(fixtureId: Int) async throws -> [Lineup] {
    guard fixtureId == script.fixture.id else { return [] }
    return script.lineups.map { $0.toLineup(fixtureId: fixtureId) }
  }

  public func otherLive() async throws -> [MatchSnapshot] {
    let snap = snapshot(for: script.other, frames: script.otherKeyframes)
    return snap.status.isLive ? [snap] : []
  }

  /// Deterministic demo stats derived from the current keyframe so the stats
  /// page has something honest to rehearse with: numbers grow as the scripted
  /// match progresses.
  public func stats(fixtureId: Int) async throws -> MatchStats? {
    guard let (_, frames) = frames(for: fixtureId),
          let frame = currentKeyframe(frames) else { return nil }
    let minute = frame.elapsed ?? 0
    let possession = 55  // scripted: home edges it all match
    func side(goals: Int, lean: Int) -> TeamStats {
      TeamStats(possession: lean,
                totalShots: goals * 3 + minute / 12,
                shotsOnGoal: goals * 2 + minute / 30,
                corners: minute / 18 + goals,
                yellowCards: minute > 30 ? 1 : 0,
                redCards: 0,
                expectedGoals: String(format: "%.2f", Double(goals) * 0.7 + Double(minute) * 0.01))
    }
    return MatchStats(home: side(goals: frame.score.home, lean: possession),
                      away: side(goals: frame.score.away, lean: 100 - possession))
  }

  /// Scripted per-player figures for the detail card (see ScriptedPlayerStats).
  public func playerStats(fixtureId: Int) async throws -> [Int: PlayerStats] {
    guard fixtureId == script.fixture.id,
          let frame = currentKeyframe(script.keyframes) else { return [:] }
    return ScriptedPlayerStats.make(lineups: script.lineups.map { $0.toLineup(fixtureId: fixtureId) },
                                    events: frame.events.map { $0.toEvent(fixtureId: fixtureId) },
                                    elapsed: frame.elapsed ?? 0)
  }
}
