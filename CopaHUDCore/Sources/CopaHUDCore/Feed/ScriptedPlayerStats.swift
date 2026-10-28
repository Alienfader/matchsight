import Foundation

/// Per-player figures for Demo mode, so the player detail card has something
/// to show in the scripted match. Invented like the scripted events, and
/// labelled the same way (the app marks the card scripted), but consistent
/// with the script: goals, assists, cards and minutes come from its events;
/// the other counts grow with minutes played at a rate set by position,
/// seeded by player id so every replay shows the same numbers. Never real
/// data, never sent to the model.
enum ScriptedPlayerStats {
  /// Per 90 minutes, by position letter.
  private struct Rates {
    var passes, shots, keyPasses, tackles, interceptions, duels, dribbles, saves: Double
  }

  private static let rates: [String: Rates] = [
    "G": Rates(passes: 30, shots: 0, keyPasses: 0, tackles: 0, interceptions: 0.5, duels: 2, dribbles: 0, saves: 3),
    "D": Rates(passes: 55, shots: 0.5, keyPasses: 0.5, tackles: 3, interceptions: 2, duels: 8, dribbles: 0.5, saves: 0),
    "M": Rates(passes: 60, shots: 1.5, keyPasses: 2, tackles: 2.5, interceptions: 1.5, duels: 10, dribbles: 1.5, saves: 0),
    "F": Rates(passes: 25, shots: 3, keyPasses: 1.5, tackles: 0.8, interceptions: 0.3, duels: 12, dribbles: 3, saves: 0),
  ]

  static func make(lineups: [Lineup], events: [MatchEvent], elapsed: Int) -> [Int: PlayerStats] {
    guard elapsed > 0 else { return [:] }
    var out: [Int: PlayerStats] = [:]
    for lineup in lineups {
      for player in lineup.startXI {
        guard let id = player.playerId else { continue }
        out[id] = stats(for: player, id: id, team: lineup.team, events: events, elapsed: elapsed)
      }
    }
    return out
  }

  private static func stats(for player: LineupPlayer, id: Int, team: Team,
                            events: [MatchEvent], elapsed: Int) -> PlayerStats {
    let mine = events.filter { $0.team.id == team.id }
    let off = mine.first { e in
      switch e.kind {
      case .substitution: return e.player == player.name
      case .card(.red): return e.playerId == id
      default: return false
      }
    }?.minute
    let minutes = min(elapsed, off ?? elapsed)

    func isScored(_ e: MatchEvent) -> Bool {
      // Own goals are left out: the feed's team for one is ambiguous here,
      // and the demo script has none.
      if case .goal(let d) = e.kind { return d == .normal || d == .penalty }
      return false
    }
    let goals = mine.filter { isScored($0) && $0.playerId == id }.count
    let assists = mine.filter { isScored($0) && $0.assist == player.name }.count
    let yellows = mine.filter { $0.kind == .card(.yellow) && $0.playerId == id }.count
    let reds = mine.filter { $0.kind == .card(.red) && $0.playerId == id }.count

    var rng = SeededGenerator(seed: UInt64(id))
    let position = player.position ?? "M"
    let r = rates[position] ?? rates["M"]!
    let share = Double(minutes) / 90
    func count(_ per90: Double) -> Int {
      Int((per90 * share * (0.7 + 0.6 * rng.next())).rounded())
    }
    func part(of total: Int, _ low: Double, _ high: Double) -> Int {
      Int((Double(total) * (low + (high - low) * rng.next())).rounded())
    }

    let passes = count(r.passes)
    let onTarget = max(goals, count(r.shots * 0.4))
    let shots = max(onTarget, count(r.shots))
    let duels = count(r.duels)
    let dribbles = count(r.dribbles)
    let isKeeper = position == "G"
    let conceded = events.filter { e in
      e.team.id != team.id && isScored(e) && e.minute <= minutes
    }.count
    let rating = min(9.9, max(5.5, 6.4 + Double(goals) * 0.8 + Double(assists) * 0.5
                                   - Double(yellows) * 0.2 - Double(reds) * 1.0 + rng.bell() * 0.3))

    return PlayerStats(
      playerId: id, passes: passes, shots: shots, tackles: count(r.tackles),
      interceptions: count(r.interceptions),
      minutes: minutes, rating: String(format: "%.1f", rating),
      goals: goals, assists: assists,
      saves: isKeeper ? count(r.saves) : nil, conceded: isKeeper ? conceded : nil,
      shotsOnTarget: onTarget, keyPasses: count(r.keyPasses),
      accuratePasses: part(of: passes, 0.75, 0.92),
      duels: duels, duelsWon: part(of: duels, 0.35, 0.65),
      dribbles: dribbles, dribblesWon: part(of: dribbles, 0.3, 0.7),
      foulsDrawn: count(1.2), foulsCommitted: count(1.0),
      yellowCards: yellows, redCards: reds)
  }
}
