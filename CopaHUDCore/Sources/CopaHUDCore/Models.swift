import Foundation

// MARK: - Contract
//
// The shared data types the feed, engine, composer and app all code against.

/// A team (national side or club) as the feed reports it.
public struct Team: Sendable, Equatable, Hashable, Codable {
  public let id: Int
  public let name: String
  /// Three-letter code from API-Football's teams endpoint ("ARS"); fixture
  /// payloads don't carry it. Additive — older encoded teams decode it as nil.
  public let code: String?
  /// Club crest (API-Football `logo`). Additive, nil when unknown.
  public let logoURL: URL?

  public init(id: Int, name: String, code: String? = nil, logoURL: URL? = nil) {
    self.id = id
    self.name = name
    self.code = code
    self.logoURL = logoURL
  }

  // Identity is id + name: code and crest are presentation metadata, so a
  // team decoded with a logo still equals the same team built without one.
  public static func == (l: Team, r: Team) -> Bool { l.id == r.id && l.name == r.name }
  public func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(name) }
}

/// API-Football short status codes, decoded leniently (unknown codes map to `.unknown`).
public enum MatchStatus: String, Sendable, Equatable, Codable {
  case notStarted = "NS"
  case firstHalf = "1H"
  case halfTime = "HT"
  case secondHalf = "2H"
  case extraTime = "ET"
  case breakTime = "BT"
  case penalties = "P"
  case finished = "FT"
  case finishedAfterExtra = "AET"
  case finishedAfterPens = "PEN"
  case suspended = "SUSP"
  case interrupted = "INT"
  case postponed = "PST"
  case cancelled = "CANC"
  case abandoned = "ABD"
  case technicalLoss = "AWD"
  case walkover = "WO"
  case live = "LIVE"
  case unknown = "UNK"

  public init(short: String) {
    self = MatchStatus(rawValue: short) ?? .unknown
  }

  public init(from decoder: any Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = MatchStatus(rawValue: raw) ?? .unknown
  }

  /// In-progress in any form (including half-time and breaks).
  public var isLive: Bool {
    switch self {
    case .firstHalf, .halfTime, .secondHalf, .extraTime, .breakTime, .penalties, .live:
      return true
    default:
      return false
    }
  }

  public var isFinished: Bool {
    switch self {
    case .finished, .finishedAfterExtra, .finishedAfterPens:
      return true
    default:
      return false
    }
  }

  /// Will never be played on today: finished, or abandoned, cancelled,
  /// postponed, awarded or a walkover. Suspended/interrupted may resume.
  public var isOver: Bool {
    switch self {
    case .postponed, .cancelled, .abandoned, .technicalLoss, .walkover:
      return true
    default:
      return isFinished
    }
  }
}

public struct ScoreLine: Sendable, Equatable, Codable {
  public var home: Int
  public var away: Int

  public init(home: Int, away: Int) {
    self.home = home
    self.away = away
  }
}

/// A scheduled or in-progress match from `todaysFixtures()`.
public struct Fixture: Sendable, Equatable, Codable, Identifiable {
  public let id: Int
  public let kickoff: Date
  public let home: Team
  public let away: Team
  /// League round label, e.g. "Group Stage - 1".
  public let groupLabel: String?
  /// Display label for the championship, e.g. "World Cup" or
  /// "Primera B · Chile" (country appended unless it's the "World"
  /// placeholder). Drives the Today list sectioning. Additive — older
  /// encoded fixtures (mock scripts) decode it as nil.
  public let competition: String?
  public let venue: String?
  public let status: MatchStatus

  public init(id: Int, kickoff: Date, home: Team, away: Team,
              groupLabel: String?, competition: String? = nil,
              venue: String?, status: MatchStatus) {
    self.id = id
    self.kickoff = kickoff
    self.home = home
    self.away = away
    self.groupLabel = groupLabel
    self.competition = competition
    self.venue = venue
    self.status = status
  }
}

/// Point-in-time state of one match: score, clock, status.
public struct MatchSnapshot: Sendable, Equatable, Codable {
  public let fixtureId: Int
  public let home: Team
  public let away: Team
  public let score: ScoreLine
  public let status: MatchStatus
  /// Match minute as the feed reports it (nil before kickoff).
  public let elapsedMinutes: Int?
  /// Home-team ball possession 0–100, when the feed has it (refreshed ≤ 1/60s).
  public let possessionHome: Int?
  public let groupLabel: String?
  public let kickoff: Date

  public init(fixtureId: Int, home: Team, away: Team, score: ScoreLine,
              status: MatchStatus, elapsedMinutes: Int?, possessionHome: Int?,
              groupLabel: String?, kickoff: Date) {
    self.fixtureId = fixtureId
    self.home = home
    self.away = away
    self.score = score
    self.status = status
    self.elapsedMinutes = elapsedMinutes
    self.possessionHome = possessionHome
    self.groupLabel = groupLabel
    self.kickoff = kickoff
  }
}

/// One feed event (goal/card/sub/VAR) with a SYNTHESIZED stable id.
///
/// API-Football events carry no id; the feed synthesizes one that is stable
/// across re-polls:
///   "\(fixtureId)-\(minute)+\(extraMinute ?? 0)-\(teamId)-\(rawType)-\(rawDetail)-\(playerId ?? 0)"
/// MatchEngine dedups on this id; it must never change for the same event.
public struct MatchEvent: Sendable, Equatable, Codable {
  public enum GoalDetail: String, Sendable, Equatable, Codable {
    case normal, ownGoal, penalty, missedPenalty
  }

  public enum CardDetail: String, Sendable, Equatable, Codable {
    case yellow, red
  }

  public enum Kind: Sendable, Equatable, Codable {
    case goal(GoalDetail)
    case card(CardDetail)
    case substitution
    /// Raw VAR detail string from the feed, e.g. "Goal cancelled",
    /// "Penalty confirmed". MatchEngine owns mapping these to outcomes.
    case varDecision(detail: String)
    case unknown(type: String, detail: String)
  }

  public let id: String
  public let fixtureId: Int
  public let minute: Int
  public let extraMinute: Int?
  public let team: Team
  public let player: String?
  /// Feed player id when known — drives headshot lookups (see PlayerPhoto).
  /// Additive: older encoded events decode it as nil.
  public let playerId: Int?
  public let assist: String?
  public let kind: Kind

  public init(id: String, fixtureId: Int, minute: Int, extraMinute: Int?,
              team: Team, player: String?, playerId: Int? = nil,
              assist: String?, kind: Kind) {
    self.id = id
    self.fixtureId = fixtureId
    self.minute = minute
    self.extraMinute = extraMinute
    self.team = team
    self.player = player
    self.playerId = playerId
    self.assist = assist
    self.kind = kind
  }
}

/// API-Sports serves player headshots at a stable CDN URL per player id.
public enum PlayerPhoto {
  public static func url(playerId: Int?) -> String? {
    playerId.map { "https://media.api-sports.io/football/players/\($0).png" }
  }
}

/// One team's match statistics — everything the stats deck page renders.
/// All optional: the feed reports what it has, the HUD shows what exists.
public struct TeamStats: Sendable, Equatable, Codable {
  public var possession: Int?      // 0–100
  public var totalShots: Int?
  public var shotsOnGoal: Int?
  public var corners: Int?
  public var yellowCards: Int?
  public var redCards: Int?
  public var expectedGoals: String?  // API serves xG as a string like "1.84"

  public init(possession: Int? = nil, totalShots: Int? = nil, shotsOnGoal: Int? = nil,
              corners: Int? = nil, yellowCards: Int? = nil, redCards: Int? = nil,
              expectedGoals: String? = nil) {
    self.possession = possession
    self.totalShots = totalShots
    self.shotsOnGoal = shotsOnGoal
    self.corners = corners
    self.yellowCards = yellowCards
    self.redCards = redCards
    self.expectedGoals = expectedGoals
  }
}

/// Home/away stats pair for one fixture.
/// One player's counters in one match (API-Football `fixtures/players`), for
/// the glasses' player cards. nil = the feed has no figure (e.g. unused sub).
public struct PlayerStats: Sendable, Equatable, Codable {
  public let playerId: Int
  public let passes: Int?
  public let shots: Int?
  public let tackles: Int?
  public let interceptions: Int?
  /// Wore the armband in this match (feed `games.captain`).
  public let isCaptain: Bool
  // Detail card (pinch on a player card). Nil when the feed has no figure.
  public let minutes: Int?
  /// The feed's match rating, verbatim ("7.2").
  public let rating: String?
  public let goals: Int?
  public let assists: Int?
  public let saves: Int?
  public let conceded: Int?
  public let shotsOnTarget: Int?
  public let keyPasses: Int?
  /// Accurate passes, a count (the feed's `passes.accuracy`).
  public let accuratePasses: Int?
  public let duels: Int?
  public let duelsWon: Int?
  public let dribbles: Int?
  public let dribblesWon: Int?
  public let foulsDrawn: Int?
  public let foulsCommitted: Int?
  public let yellowCards: Int?
  public let redCards: Int?

  public init(playerId: Int, passes: Int?, shots: Int?, tackles: Int?, interceptions: Int?,
              isCaptain: Bool = false, minutes: Int? = nil, rating: String? = nil,
              goals: Int? = nil, assists: Int? = nil, saves: Int? = nil, conceded: Int? = nil,
              shotsOnTarget: Int? = nil, keyPasses: Int? = nil, accuratePasses: Int? = nil,
              duels: Int? = nil, duelsWon: Int? = nil, dribbles: Int? = nil, dribblesWon: Int? = nil,
              foulsDrawn: Int? = nil, foulsCommitted: Int? = nil,
              yellowCards: Int? = nil, redCards: Int? = nil) {
    self.isCaptain = isCaptain
    self.playerId = playerId
    self.passes = passes
    self.shots = shots
    self.tackles = tackles
    self.interceptions = interceptions
    self.minutes = minutes
    self.rating = rating
    self.goals = goals
    self.assists = assists
    self.saves = saves
    self.conceded = conceded
    self.shotsOnTarget = shotsOnTarget
    self.keyPasses = keyPasses
    self.accuratePasses = accuratePasses
    self.duels = duels
    self.duelsWon = duelsWon
    self.dribbles = dribbles
    self.dribblesWon = dribblesWon
    self.foulsDrawn = foulsDrawn
    self.foulsCommitted = foulsCommitted
    self.yellowCards = yellowCards
    self.redCards = redCards
  }
}

/// API-Football's pre-match prediction, in percent (home + draw + away ≈ 100).
public struct WinProbability: Sendable, Equatable, Codable {
  public enum Side: Sendable, Equatable { case home, away }
  public let home: Int
  public let draw: Int
  public let away: Int

  public init(home: Int, draw: Int, away: Int) {
    self.home = home
    self.draw = draw
    self.away = away
  }

  /// The side more likely to win, when one is strictly ahead of the other.
  public var favourite: Side? {
    if home > away { return .home }
    if away > home { return .away }
    return nil
  }
}

public struct MatchStats: Sendable, Equatable, Codable {
  public var home: TeamStats
  public var away: TeamStats

  public init(home: TeamStats, away: TeamStats) {
    self.home = home
    self.away = away
  }
}

public struct LineupPlayer: Sendable, Equatable, Codable {
  public let name: String
  public let number: Int?
  /// Feed position letter: G/D/M/F.
  public let position: String?
  /// Feed grid like "4:2" (row:column), when present.
  public let grid: String?
  /// Feed player id when known — drives the player-card headshot. Additive.
  public let playerId: Int?

  public init(name: String, number: Int?, position: String?, grid: String?,
              playerId: Int? = nil) {
    self.name = name
    self.number = number
    self.position = position
    self.grid = grid
    self.playerId = playerId
  }
}

public struct Lineup: Sendable, Equatable, Codable {
  public let fixtureId: Int
  public let team: Team
  public let formation: String?
  public let startXI: [LineupPlayer]
  public let coach: String?

  public init(fixtureId: Int, team: Team, formation: String?,
              startXI: [LineupPlayer], coach: String?) {
    self.fixtureId = fixtureId
    self.team = team
    self.formation = formation
    self.startXI = startXI
    self.coach = coach
  }
}

/// Shared error vocabulary so the phone UI can show honest banners.
public enum FeedError: Error, Sendable, Equatable {
  case unauthorized
  case quotaExceeded
  case network(String)
  case decoding(String)
}
