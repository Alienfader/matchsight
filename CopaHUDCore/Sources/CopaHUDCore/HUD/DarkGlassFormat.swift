import Foundation

/// One figure on the dark glass player page: "76" over "PASSES · 96%".
public struct StatTile: Sendable, Equatable {
  public var value: String
  public var label: String

  public init(value: String, label: String) {
    self.value = value
    self.label = label
  }
}

/// One line of the dark glass Live page: "70' 🟨 Renê FLU".
public struct LatestEvent: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case goal, ownGoal, penalty, missedPenalty, yellow, red, varCheck
  }
  public var minute: String
  public var kind: Kind
  public var name: String
  public var team: String
}

/// Text choices for the dark glass pages: fewer, bigger, no zeros.
public enum DarkGlassFormat {
  /// Names longer than this show the surname only.
  static let maxNameLength = 14

  /// A long feed name shortens to the surname; a short one stays whole.
  public static func displayName(_ name: String) -> String {
    name.count > maxNameLength ? HUDFormat.splitName(name).last : name
  }

  /// Goals, cards and VAR checks, newest first. Substitutions are left out.
  /// A starter shows under his lineup name (the feed's events use full
  /// names: "Renê Rodrigues Martins" is Renê).
  public static func latest(_ events: [MatchEvent], lineups: [Lineup] = [], limit: Int = 3) -> [LatestEvent] {
    var known: [Int: String] = [:]
    for player in lineups.flatMap(\.startXI) {
      if let id = player.playerId { known[id] = player.name }
    }
    return events.sorted { ($0.minute, $0.extraMinute ?? 0) > ($1.minute, $1.extraMinute ?? 0) }
      .compactMap { e -> LatestEvent? in
        let kind: LatestEvent.Kind
        switch e.kind {
        case .goal(.normal): kind = .goal
        case .goal(.ownGoal): kind = .ownGoal
        case .goal(.penalty): kind = .penalty
        case .goal(.missedPenalty): kind = .missedPenalty
        case .card(.yellow): kind = .yellow
        case .card(.red): kind = .red
        case .varDecision: kind = .varCheck
        case .substitution, .unknown: return nil
        }
        let name = e.playerId.flatMap { known[$0] } ?? e.player ?? "—"
        return LatestEvent(minute: HUDFormat.minuteLabel(e.minute, extra: e.extraMinute), kind: kind,
                           name: displayName(name),
                           team: TeamStyle.style(for: e.team).code)
      }
      .prefix(limit).map { $0 }
  }

  /// Up to four figures for a player: goals and assists first when they
  /// have any, then what matters for the position. Zeros are left out,
  /// except a keeper's goals conceded.
  public static func keyFigures(position: String?, stats: PlayerStats?) -> [StatTile] {
    guard let s = stats else { return [] }
    func count(_ v: Int?, _ label: String) -> StatTile? {
      guard let v, v > 0 else { return nil }
      return StatTile(value: "\(v)", label: label)
    }
    let passes: StatTile? = {
      guard let p = s.passes, p > 0 else { return nil }
      guard let a = s.accuratePasses else { return StatTile(value: "\(p)", label: "PASSES") }
      return StatTile(value: "\(p)", label: "PASSES · \(Int((Double(a) * 100 / Double(p)).rounded()))%")
    }()
    let shots: StatTile? = {
      guard let n = s.shots, n > 0 else { return nil }
      let on = s.shotsOnTarget ?? 0
      return StatTile(value: "\(n)", label: on > 0 ? "SHOTS · \(on) ON TARGET" : "SHOTS")
    }()
    func ratio(_ won: Int?, _ of: Int?, _ label: String) -> StatTile? {
      guard let won, won > 0, let of else { return nil }
      return StatTile(value: "\(won)/\(of)", label: label)
    }
    let duels = ratio(s.duelsWon, s.duels, "DUELS WON")
    let dribbles = ratio(s.dribblesWon, s.dribbles, "DRIBBLES")
    let keyPasses = count(s.keyPasses, "KEY PASSES")
    let tackles = count(s.tackles, "TACKLES")
    let interceptions = count(s.interceptions, "INTERCEPTIONS")

    let byPosition: [StatTile?]
    switch position?.uppercased().first {
    case "G":
      byPosition = [count(s.saves, "SAVES"), s.conceded.map { StatTile(value: "\($0)", label: "CONCEDED") },
                    passes, duels]
    case "D":
      byPosition = [passes, tackles, interceptions, duels, keyPasses, shots]
    case "F":
      byPosition = [shots, keyPasses, dribbles, passes, duels]
    default:
      byPosition = [passes, keyPasses, shots, duels, tackles, dribbles]
    }
    let lead = [count(s.goals, "GOALS"), count(s.assists, "ASSISTS")]
    return (lead + byPosition).compactMap { $0 }.prefix(4).map { $0 }
  }
}
