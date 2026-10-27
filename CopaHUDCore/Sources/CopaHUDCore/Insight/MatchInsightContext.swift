import Foundation

// The ONLY match data the AI analyst sees. Every fact is something the feed
// actually reported — missing data is omitted, never guessed — and carries an
// id ("F1"…) the model must cite, so InsightValidator can reject claims that
// point at facts we never sent.

/// One numbered, human-readable match fact.
public struct InsightFact: Sendable, Equatable {
  public let id: String
  public let text: String

  public init(id: String, text: String) {
    self.id = id
    self.text = text
  }
}

/// Grounded match context for one insight request.
public struct MatchInsightContext: Sendable, Equatable {
  public let fixtureId: Int
  /// "Brazil vs Morocco · Group Stage - 1 · 67'" — the only part with the clock.
  public let headline: String
  public let facts: [InsightFact]
  /// True for demo-mode data; the prompt labels it SCRIPTED.
  public let isScripted: Bool

  public init(fixtureId: Int, headline: String, facts: [InsightFact], isScripted: Bool) {
    self.fixtureId = fixtureId
    self.headline = headline
    self.facts = facts
    self.isScripted = isScripted
  }

  /// Clock-free identity of the facts: unchanged data → unchanged fingerprint,
  /// so the coordinator never re-asks the model just because a minute ticked.
  public var fingerprint: String { facts.map(\.text).joined(separator: "\n") }

  public func factIDs() -> Set<String> { Set(facts.map(\.id)) }

  /// Max events kept as facts (most recent), so the prompt stays small.
  static let maxEvents = 12

  public static func build(snapshot: MatchSnapshot, events: [MatchEvent], lineups: [Lineup],
                           stats: MatchStats?, isScripted: Bool) -> MatchInsightContext {
    let home = snapshot.home.name
    let away = snapshot.away.name
    var texts: [String] = []

    texts.append("Score: \(home) \(snapshot.score.home)–\(snapshot.score.away) \(away)")
    texts.append("Phase: \(phaseText(snapshot.status))")

    for team in [snapshot.home, snapshot.away] {
      guard let lineup = lineups.first(where: { $0.team.id == team.id }),
            let formation = lineup.formation else { continue }
      let coach = lineup.coach.map { " (coach \($0))" } ?? ""
      texts.append("\(team.name) formation: \(formation)\(coach)")
    }

    let chronological = events
      .filter { if case .unknown = $0.kind { return false } else { return true } }
      .sorted { ($0.minute, $0.extraMinute ?? 0) < ($1.minute, $1.extraMinute ?? 0) }
    texts.append(contentsOf: chronological.suffix(maxEvents).compactMap(eventText))

    texts.append(contentsOf: statsTexts(stats, snapshot: snapshot))

    let facts = texts.enumerated().map { InsightFact(id: "F\($0.offset + 1)", text: $0.element) }

    var headlineParts = ["\(home) vs \(away)"]
    if let group = snapshot.groupLabel { headlineParts.append(group) }
    headlineParts.append(snapshot.elapsedMinutes.map { HUDFormat.minuteLabel($0, extra: nil) }
                         ?? phaseText(snapshot.status))

    return MatchInsightContext(fixtureId: snapshot.fixtureId,
                               headline: headlineParts.joined(separator: " · "),
                               facts: facts, isScripted: isScripted)
  }

  // MARK: - Fact text

  static func phaseText(_ status: MatchStatus) -> String {
    switch status {
    case .notStarted: return "Not started"
    case .firstHalf: return "1st half"
    case .halfTime: return "Half-time"
    case .secondHalf: return "2nd half"
    case .extraTime: return "Extra time"
    case .breakTime: return "Break"
    case .penalties: return "Penalty shootout"
    case .finished, .finishedAfterExtra, .finishedAfterPens: return "Full time"
    default: return status.rawValue
    }
  }

  /// "18' GOAL Brazil: Raphinha (assist Vinícius Júnior)". API-Football subst
  /// events report the player going OFF as `player` and the one coming ON as
  /// `assist` (verified against recorded real JSON).
  private static func eventText(_ e: MatchEvent) -> String? {
    let prefix = "\(HUDFormat.minuteLabel(e.minute, extra: e.extraMinute))"
    let who = e.player.map { ": \($0)" } ?? ""
    switch e.kind {
    case let .goal(detail):
      let label: String
      switch detail {
      case .normal: label = "GOAL"
      case .penalty: label = "GOAL (penalty)"
      case .ownGoal: label = "OWN GOAL"
      case .missedPenalty: label = "MISSED PENALTY"
      }
      let assist = (detail == .normal || detail == .penalty)
        ? e.assist.map { " (assist \($0))" } ?? "" : ""
      return "\(prefix) \(label) \(e.team.name)\(who)\(assist)"
    case .card(.yellow):
      return "\(prefix) YELLOW CARD \(e.team.name)\(who)"
    case .card(.red):
      return "\(prefix) RED CARD \(e.team.name)\(who)"
    case .substitution:
      var parts: [String] = []
      if let on = e.assist { parts.append("\(on) on") }
      if let off = e.player { parts.append("\(off) off") }
      let detail = parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")
      return "\(prefix) SUB \(e.team.name)\(detail)"
    case let .varDecision(detail):
      return "\(prefix) VAR \(e.team.name): \(detail)"
    case .unknown:
      return nil
    }
  }

  /// Stat rows only where BOTH sides are known — the model never sees a "?".
  private static func statsTexts(_ stats: MatchStats?, snapshot: MatchSnapshot) -> [String] {
    let home = snapshot.home.name
    let away = snapshot.away.name
    var texts: [String] = []

    if let h = stats?.home.possession, let a = stats?.away.possession {
      texts.append("Possession: \(home) \(h)% – \(away) \(a)%")
    } else if let h = snapshot.possessionHome {
      texts.append("Possession: \(home) \(h)% – \(away) \(100 - h)%")
    }
    guard let stats else { return texts }

    func row(_ label: String, _ h: Int?, _ a: Int?) {
      guard let h, let a else { return }
      texts.append("\(label): \(home) \(h) – \(away) \(a)")
    }
    row("Shots", stats.home.totalShots, stats.away.totalShots)
    row("Shots on target", stats.home.shotsOnGoal, stats.away.shotsOnGoal)
    row("Corners", stats.home.corners, stats.away.corners)
    row("Yellow cards", stats.home.yellowCards, stats.away.yellowCards)
    row("Red cards", stats.home.redCards, stats.away.redCards)
    if let h = stats.home.expectedGoals, let a = stats.away.expectedGoals {
      texts.append("xG: \(home) \(h) – \(away) \(a)")
    }
    return texts
  }
}
