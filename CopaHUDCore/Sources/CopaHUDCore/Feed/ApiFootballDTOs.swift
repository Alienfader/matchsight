import Foundation

// MARK: - API-Football v3 wire DTOs
//
// These mirror the JSON shapes documented at
// https://www.api-football.com/documentation-v3 exactly as the paid tier
// returns them. They are intentionally lenient: unknown keys are ignored by
// Codable, optional fields stay optional, and the `errors` envelope field is
// decoded whether it arrives as `[]` (empty) or as an object of messages.
//
// Nothing here is public — the feed maps these into the shared contract
// types (Fixture / MatchSnapshot / MatchEvent / Lineup) before anything leaves
// the module.

/// The envelope wrapping every API-Football response.
struct ApiResponse<T: Decodable>: Decodable {
  let results: Int?
  let errors: ApiErrors
  let response: [T]

  enum CodingKeys: String, CodingKey { case results, errors, response }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    results = try c.decodeIfPresent(Int.self, forKey: .results)
    errors = try c.decodeIfPresent(ApiErrors.self, forKey: .errors) ?? ApiErrors(messages: [])
    response = (try? c.decodeIfPresent([T].self, forKey: .response)) ?? []
  }
}

/// API-Football's `errors` field is `[]` when there are none, but becomes an
/// object like `{"token": "...", "requests": "..."}` when something is wrong.
/// We flatten both keys and values into `messages` for classification.
struct ApiErrors: Decodable {
  let messages: [String]

  init(messages: [String]) { self.messages = messages }

  init(from decoder: any Decoder) throws {
    // Empty form: an array (usually []).
    if var unkeyed = try? decoder.unkeyedContainer() {
      var collected: [String] = []
      while !unkeyed.isAtEnd {
        if let s = try? unkeyed.decode(String.self) {
          collected.append(s)
        } else {
          _ = try? unkeyed.decode(AnyCodable.self)
        }
      }
      messages = collected
      return
    }
    // Error form: an object whose keys and values are both informative.
    if let keyed = try? decoder.container(keyedBy: DynamicKey.self) {
      var collected: [String] = []
      for key in keyed.allKeys {
        collected.append(key.stringValue)
        if let value = try? keyed.decode(String.self, forKey: key) {
          collected.append(value)
        }
      }
      messages = collected
      return
    }
    messages = []
  }

  var isEmpty: Bool { messages.isEmpty }
}

private struct DynamicKey: CodingKey {
  var stringValue: String
  var intValue: Int?
  init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
  init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

/// Swallows any JSON value we don't care about (used to skip array entries).
private struct AnyCodable: Decodable {
  init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { return }
    if (try? c.decode(Bool.self)) != nil { return }
    if (try? c.decode(Double.self)) != nil { return }
    if (try? c.decode(String.self)) != nil { return }
    if (try? c.decode([String: AnyCodable].self)) != nil { return }
    if (try? c.decode([AnyCodable].self)) != nil { return }
  }
}

// MARK: - Fixtures

struct FixtureDTO: Decodable {
  let fixture: FixtureInfoDTO
  let league: LeagueDTO
  let teams: TeamsDTO
  let goals: GoalsDTO
}

struct FixtureInfoDTO: Decodable {
  let id: Int
  let date: String
  let timestamp: Int?
  let venue: VenueDTO?
  let status: StatusDTO
}

struct VenueDTO: Decodable {
  let name: String?
  let city: String?
}

struct StatusDTO: Decodable {
  let long: String?
  let short: String
  let elapsed: Int?
}

struct LeagueDTO: Decodable {
  let id: Int?
  let name: String?
  let country: String?
  let season: Int?
  let round: String?
}

extension LeagueDTO {
  /// "Primera B · Chile"; country dropped when missing or the "World"
  /// placeholder API-Football uses for international competitions.
  var competitionLabel: String? {
    guard let name, !name.isEmpty else { return nil }
    guard let country, !country.isEmpty, country != "World" else { return name }
    return "\(name) · \(country)"
  }
}

struct TeamsDTO: Decodable {
  let home: TeamDTO
  let away: TeamDTO
}

struct TeamDTO: Decodable {
  let id: Int
  let name: String
  /// Crest URL; `winner` and `colors` exist on the wire but the contract drops them.
  let logo: String?

  var team: Team { Team(id: id, name: name, logoURL: logo.flatMap(URL.init(string:))) }
}

/// `/teams` entry: `{ "team": { id, name, code, logo, … }, "venue": … }`.
struct TeamInfoDTO: Decodable {
  let team: TeamCatalogDTO
}

struct TeamCatalogDTO: Decodable {
  let id: Int
  let name: String
  let code: String?
  let logo: String?

  var team: Team { Team(id: id, name: name, code: code, logoURL: logo.flatMap(URL.init(string:))) }
}

struct GoalsDTO: Decodable {
  let home: Int?
  let away: Int?
}

// MARK: - Events

struct EventDTO: Decodable {
  let time: EventTimeDTO
  let team: TeamDTO
  let player: PersonDTO?
  let assist: PersonDTO?
  let type: String
  let detail: String
  let comments: String?
}

struct EventTimeDTO: Decodable {
  let elapsed: Int
  let extra: Int?
}

struct PersonDTO: Decodable {
  let id: Int?
  let name: String?
}

// MARK: - Lineups

struct LineupDTO: Decodable {
  let team: TeamDTO
  let formation: String?
  let startXI: [LineupSlotDTO]
  let coach: CoachDTO?
}

struct LineupSlotDTO: Decodable {
  let player: LineupPlayerDTO
}

struct LineupPlayerDTO: Decodable {
  let id: Int?
  let name: String?
  let number: Int?
  let pos: String?
  let grid: String?
}

struct CoachDTO: Decodable {
  let id: Int?
  let name: String?
}

// MARK: - Player statistics (fixtures/players)

struct PlayersTeamDTO: Decodable {
  let team: TeamDTO
  let players: [PlayerEntryDTO]

  var playerStats: [PlayerStats] { players.compactMap(\.playerStats) }
}

struct PlayerEntryDTO: Decodable {
  struct Player: Decodable { let id: Int }
  struct Stat: Decodable {
    struct Games: Decodable { let minutes: Int?; let captain: Bool?; let rating: String? }
    struct Shots: Decodable { let total: Int?; let on: Int? }
    struct Passes: Decodable { let total: Int?; let key: Int?; let accuracy: String? }
    struct Tackles: Decodable { let total: Int?; let interceptions: Int? }
    struct Goals: Decodable { let total: Int?; let conceded: Int?; let assists: Int?; let saves: Int? }
    struct Duels: Decodable { let total: Int?; let won: Int? }
    struct Dribbles: Decodable { let attempts: Int?; let success: Int? }
    struct Fouls: Decodable { let drawn: Int?; let committed: Int? }
    struct Cards: Decodable { let yellow: Int?; let red: Int? }
    let games: Games?
    let shots: Shots?
    let passes: Passes?
    let tackles: Tackles?
    let goals: Goals?
    let duels: Duels?
    let dribbles: Dribbles?
    let fouls: Fouls?
    let cards: Cards?
  }
  let player: Player
  let statistics: [Stat]

  /// The feed sends null for a zero counter, so for a player who played a
  /// null counts as 0; a player with no minutes has no figures at all.
  var playerStats: PlayerStats? {
    guard let s = statistics.first else { return nil }
    let played = (s.games?.minutes ?? 0) > 0
    func value(_ v: Int?) -> Int? { played ? (v ?? 0) : v }
    return PlayerStats(playerId: player.id, passes: value(s.passes?.total),
                       shots: value(s.shots?.total), tackles: value(s.tackles?.total),
                       interceptions: value(s.tackles?.interceptions),
                       isCaptain: s.games?.captain ?? false,
                       minutes: s.games?.minutes, rating: s.games?.rating,
                       goals: value(s.goals?.total), assists: value(s.goals?.assists),
                       saves: value(s.goals?.saves), conceded: value(s.goals?.conceded),
                       shotsOnTarget: value(s.shots?.on), keyPasses: value(s.passes?.key),
                       accuratePasses: value(s.passes?.accuracy.flatMap { Int($0) }),
                       duels: value(s.duels?.total), duelsWon: value(s.duels?.won),
                       dribbles: value(s.dribbles?.attempts), dribblesWon: value(s.dribbles?.success),
                       foulsDrawn: value(s.fouls?.drawn), foulsCommitted: value(s.fouls?.committed),
                       yellowCards: value(s.cards?.yellow), redCards: value(s.cards?.red))
  }
}

// MARK: - Predictions

struct PredictionDTO: Decodable {
  struct Predictions: Decodable {
    struct Percent: Decodable { let home: String?; let draw: String?; let away: String? }
    let percent: Percent?
  }
  let predictions: Predictions

  /// "45%" strings → integers; nil unless all three parse.
  var winProbability: WinProbability? {
    func pct(_ s: String?) -> Int? { s.flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
    guard let p = predictions.percent, let h = pct(p.home), let d = pct(p.draw), let a = pct(p.away) else {
      return nil
    }
    return WinProbability(home: h, draw: d, away: a)
  }
}

// MARK: - Statistics (possession is the only field the contract wants)

struct StatisticsDTO: Decodable {
  let team: TeamDTO
  let statistics: [StatItemDTO]
}

struct StatItemDTO: Decodable {
  let type: String
  let value: StatValue
}

/// A statistic value arrives as null, an Int, or a String like "65%".
enum StatValue: Decodable {
  case string(String)
  case int(Int)
  case null

  init(from decoder: any Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null; return }
    if let i = try? c.decode(Int.self) { self = .int(i); return }
    if let s = try? c.decode(String.self) { self = .string(s); return }
    self = .null
  }

  /// Best-effort whole-number reading: "65%" → 65, 65 → 65, null → nil.
  var intValue: Int? {
    switch self {
    case .int(let i):
      return i
    case .string(let s):
      let digits = s.replacingOccurrences(of: "%", with: "")
        .trimmingCharacters(in: .whitespaces)
      return Int(digits)
    case .null:
      return nil
    }
  }

  /// String reading for non-integer stats (xG arrives as "1.84").
  var stringValue: String? {
    switch self {
    case .int(let i): return String(i)
    case .string(let s): return s
    case .null: return nil
    }
  }
}
