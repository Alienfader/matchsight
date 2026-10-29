import Foundation

/// Pure formatting for every string the HUD shows. Kept separate from the
/// stateful `HUDComposer` so each piece is unit-testable in isolation and so
/// the app-side `HUDBuilder` can reuse the bits it needs (e.g. the possession
/// bar) without re-deriving them.
public enum HUDFormat {
  private static let filledGlyph = "▰"
  private static let emptyGlyph = "▱"

  /// 10-glyph possession bar for the home team, e.g. 65 → "▰▰▰▰▰▰▱▱▱▱".
  /// Out-of-range values clamp; result is always exactly 10 glyphs.
  public static func possessionBar(home: Int) -> String {
    let clamped = min(100, max(0, home))
    let filled = clamped / 10
    return String(repeating: filledGlyph, count: filled)
      + String(repeating: emptyGlyph, count: 10 - filled)
  }

  /// "67'" or "45+2'".
  public static func minuteLabel(_ minute: Int, extra: Int?) -> String {
    if let extra, extra > 0 { return "\(minute)+\(extra)'" }
    return "\(minute)'"
  }

  /// Local kickoff time "HH:mm" (24h), for pre-kickoff panels.
  public static func kickoffTime(_ date: Date) -> String {
    kickoffFormatter.string(from: date)
  }

  private static let kickoffFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "HH:mm"
    return f
  }()

  /// FIFA trigram for a national team, club code for a club.
  public static func code(_ team: Team) -> String {
    TeamStyle.style(for: team).code
  }

  /// "🇧🇷 BRA 2 · 1 ARG 🇦🇷", or "ARS 2 · 1 CHE" for clubs (no flags).
  public static func scoreLine(home: Team, away: Team, score: ScoreLine) -> String {
    let h = TeamStyle.style(for: home)
    let a = TeamStyle.style(for: away)
    return "\(flagged(h.flag, h.code)) \(score.home) · \(score.away) \(flagged(a.code, a.flag))"
  }

  /// Joins a flag and a label with a space, dropping the space when the
  /// flag is empty (clubs).
  public static func flagged(_ a: String, _ b: String) -> String {
    [a, b].filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// One STARTING XI carousel card, demo-style. Position rides its own field
  /// (rendered beside the number) instead of being buried in the team line.
  public static func playerCard(lineup: Lineup, cardIndex: Int) -> PlayerCardContent {
    let player = lineup.startXI[cardIndex]
    let (first, last) = splitName(player.name)
    return PlayerCardContent(
      teamLine: lineupTitle(lineup),
      firstName: first,
      lastName: last,
      number: player.number.map(String.init) ?? "–",
      positionLabel: positionLabel(player.position),
      photoURL: PlayerPhoto.url(playerId: player.playerId),
      dots: dots(index: cardIndex, count: lineup.startXI.count),
      counter: "\(cardIndex + 1)/\(lineup.startXI.count)")
  }

  /// Detail card rows: only figures the feed sent for a player who played,
  /// keeper figures for a keeper, cards only when shown. Empty without stats.
  public static func playerDetailRows(_ s: PlayerStats?, position: String?) -> [PlayerStatRow] {
    guard let s, (s.minutes ?? 0) > 0 else { return [] }
    var rows: [PlayerStatRow] = []
    func add(_ label: String, _ value: String?) {
      if let value { rows.append(PlayerStatRow(label: label, value: value)) }
    }
    func count(_ v: Int?) -> String? { v.map(String.init) }
    func withPart(_ total: Int?, _ part: Int?, _ word: String) -> String? {
      guard let total else { return nil }
      return part.map { "\(total) (\($0) \(word))" } ?? "\(total)"
    }
    func outOf(_ won: Int?, _ total: Int?) -> String? {
      guard let won, let total else { return nil }
      return "\(won) of \(total)"
    }
    if position == "G" {
      add("Saves", count(s.saves))
      add("Conceded", count(s.conceded))
      add("Passes", withPart(s.passes, s.accuratePasses, "accurate"))
      add("Duels won", outOf(s.duelsWon, s.duels))
    } else {
      add("Goals", count(s.goals))
      add("Assists", count(s.assists))
      add("Shots", withPart(s.shots, s.shotsOnTarget, "on target"))
      add("Key passes", count(s.keyPasses))
      add("Passes", withPart(s.passes, s.accuratePasses, "accurate"))
      add("Tackles", count(s.tackles))
      add("Interceptions", count(s.interceptions))
      add("Duels won", outOf(s.duelsWon, s.duels))
      add("Dribbles", outOf(s.dribblesWon, s.dribbles))
    }
    add("Fouls", count(s.foulsCommitted))
    let cards = [(s.yellowCards ?? 0, "yellow"), (s.redCards ?? 0, "red")]
      .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
    if !cards.isEmpty { add("Cards", cards.joined(separator: " · ")) }
    return rows
  }

  /// "Rating 7.2 · 52 min"; nil for a player who hasn't played.
  public static func playerSummary(_ s: PlayerStats?) -> String? {
    guard let s, let minutes = s.minutes, minutes > 0 else { return nil }
    return (s.rating.map { "Rating \($0) · " } ?? "") + "\(minutes) min"
  }

  /// STARTING XI index card — the carousel's front page: whole XI grouped by
  /// position, coach, and a pinch hint so the band gesture is discoverable.
  public static func rosterIndex(_ lineup: Lineup) -> LineupContent {
    LineupContent(
      title: lineupTitle(lineup),
      rows: lineupRows(lineup),
      coachLine: lineup.coach.map { "COACH \($0)" },
      footer: "\(lineup.startXI.count) player\(lineup.startXI.count == 1 ? "" : "s") · pinch ›")
  }

  /// "Matvey Safonov" → ("Matvey", "Safonov"); single names → ("", name).
  public static func splitName(_ name: String) -> (first: String, last: String) {
    let parts = name.split(separator: " ")
    guard parts.count > 1, let last = parts.last else { return ("", name) }
    return (parts.dropLast().joined(separator: " "), String(last))
  }

  /// "○○●○○○○○○○○" compact carousel position indicator — unspaced so a full
  /// XI fits beside the n/11 counter on one footer row.
  public static func dots(index: Int, count: Int) -> String {
    (0..<max(count, 1)).map { $0 == index ? "●" : "○" }.joined()
  }

  /// G/D/M/F → GK/DEF/MID/FWD.
  public static func positionLabel(_ pos: String?) -> String? {
    switch pos?.uppercased() {
    case "G": return "GK"
    case "D": return "DEF"
    case "M": return "MID"
    case "F": return "FWD"
    default: return nil
    }
  }

  /// Stats-page lines: possession bar first, then home · away value rows.
  /// Rows with no data on either side are omitted — the page shows what the
  /// feed actually knows.
  public static func statsLines(_ stats: MatchStats) -> [String] {
    var lines: [String] = []
    if let p = stats.home.possession {
      lines.append("POSS  \(possessionBar(home: p))  \(p)%")
    }
    func row(_ label: String, _ home: Int?, _ away: Int?) {
      guard home != nil || away != nil else { return }
      lines.append("\(label)  \(home.map(String.init) ?? "–") · \(away.map(String.init) ?? "–")")
    }
    row("SHOTS", stats.home.totalShots, stats.away.totalShots)
    row("ON TGT", stats.home.shotsOnGoal, stats.away.shotsOnGoal)
    row("CORNERS", stats.home.corners, stats.away.corners)
    row("CARDS", stats.home.yellowCards, stats.away.yellowCards)
    if stats.home.expectedGoals != nil || stats.away.expectedGoals != nil {
      lines.append("xG  \(stats.home.expectedGoals ?? "–") · \(stats.away.expectedGoals ?? "–")")
    }
    return lines.isEmpty ? ["no stats yet"] : lines
  }

  /// One events-page line, newest first: "67' ⚽ Neymar (BRA)".
  public static func eventLine(_ event: MatchEvent) -> String {
    let prefix = minuteLabel(event.minute, extra: event.extraMinute)
    let teamCode = code(event.team)
    let who = event.player ?? "—"
    switch event.kind {
    case .goal:
      return "\(prefix) ⚽ \(who) (\(teamCode))"
    case .card(.red):
      return "\(prefix) 🟥 \(who) (\(teamCode))"
    case .card(.yellow):
      return "\(prefix) 🟨 \(who) (\(teamCode))"
    case .substitution:
      return "\(prefix) 🔁 \(who) (\(teamCode))"
    case let .varDecision(detail):
      return "\(prefix) VAR: \(detail)"
    case let .unknown(type, _):
      return "\(prefix) \(type) (\(teamCode))"
    }
  }

  /// One other-live line: "FRA 2·0 GER · 78'". Minute reflects status (HT/FT).
  public static func otherLiveLine(_ snap: MatchSnapshot) -> String {
    let h = code(snap.home)
    let a = code(snap.away)
    let base = "\(h) \(snap.score.home)·\(snap.score.away) \(a)"
    if let clock = compactClock(status: snap.status, elapsed: snap.elapsedMinutes) {
      return "\(base) · \(clock)"
    }
    return base
  }

  /// Cross-match toast: "⚽ FRA 2·0 GER · Mbappé 84'" (scorer omitted when nil).
  public static func toastLine(snapshot: MatchSnapshot, scorer: String?, minute: Int?) -> String {
    let h = code(snapshot.home)
    let a = code(snapshot.away)
    var line = "⚽ \(h) \(snapshot.score.home)·\(snapshot.score.away) \(a)"
    if let scorer {
      let min = minute ?? snapshot.elapsedMinutes
      if let min { line += " · \(scorer) \(min)'" } else { line += " · \(scorer)" }
    }
    return line
  }

  /// "🇧🇷 Brazil · 4-2-3-1" (formation omitted when nil).
  public static func lineupTitle(_ lineup: Lineup) -> String {
    let name = flagged(TeamStyle.style(for: lineup.team).flag, lineup.team.name)
    if let formation = lineup.formation, !formation.isEmpty {
      return "\(name) · \(formation)"
    }
    return name
  }

  /// XI grouped into GK / DEF / MID / FWD rows, surnames only.
  public static func lineupRows(_ lineup: Lineup) -> [String] {
    let order: [(label: String, group: PositionGroup)] = [
      ("GK", .goalkeeper), ("DEF", .defender), ("MID", .midfielder), ("FWD", .forward),
    ]
    var rows: [String] = []
    for entry in order {
      let surnames = lineup.startXI
        .filter { positionGroup(of: $0) == entry.group }
        .map { surname(of: $0.name) }
      if !surnames.isEmpty {
        rows.append("\(entry.label) \(surnames.joined(separator: ", "))")
      }
    }
    return rows
  }

  /// Full takeover banner for a followed-match moment.
  public static func takeover(moment: MatchMoment, home: Team, away: Team) -> TakeoverContent {
    let score = scoreLine(home: home, away: away, score: moment.score)
    switch moment.kind {
    case let .goal(scorer, assist, detail):
      let headline: String
      switch detail {
      case .ownGoal: headline = "OWN GOAL ⚽"
      case .penalty: headline = "PENALTY GOAL ⚽"
      default: headline = "GOOOAAALL! ⚽"
      }
      return TakeoverContent(headline: headline, scoreLine: score,
                             detail: goalDetail(scorer: scorer, assist: assist, minute: moment.minute),
                             imageURL: PlayerPhoto.url(playerId: moment.playerId))
    case let .redCard(player, _):
      let detail = player.map { p in
        moment.minute.map { "\(p) \($0)'" } ?? p
      } ?? moment.minute.map { "\($0)'" }
      return TakeoverContent(headline: "🟥 SENT OFF", scoreLine: score, detail: detail,
                             imageURL: PlayerPhoto.url(playerId: moment.playerId))
    case let .penaltyAwarded(team):
      return TakeoverContent(headline: "PEN to \(code(team))", scoreLine: score, detail: nil)
    case let .varDecision(outcome):
      return TakeoverContent(headline: varHeadline(outcome), scoreLine: score, detail: nil)
    case .halfTime:
      return TakeoverContent(headline: "HALF-TIME", scoreLine: score, detail: nil)
    case .fullTime:
      return TakeoverContent(headline: "FULL-TIME", scoreLine: score, detail: nil)
    case let .otherMatchGoal(snapshot, scorer):
      // otherMatchGoal is normally a toast; provide an honest banner if it ever
      // reaches here so nothing renders blank.
      return TakeoverContent(headline: "⚽ GOAL",
                             scoreLine: scoreLine(home: snapshot.home, away: snapshot.away,
                                                  score: snapshot.score),
                             detail: scorer)
    case .yellowCard, .substitution, .shotOnTarget:
      // Notices are toasts; the same line if one ever reaches here.
      return TakeoverContent(headline: noticeLine(moment.kind, minute: moment.minute) ?? "",
                             scoreLine: score, detail: nil)
    }
  }

  /// The toast line for a notice: "🟨 Martins · FLU 70'",
  /// "🔁 Lima on for Hulk · FLU 58'", "🎯 Shot on target · INT (2)".
  public static func noticeLine(_ kind: MatchMoment.Kind, minute: Int?) -> String? {
    let at = minute.map { " \($0)'" } ?? ""
    switch kind {
    case let .yellowCard(player, team):
      return "🟨 \(DarkGlassFormat.displayName(player ?? "Yellow card")) · \(code(team))\(at)"
    case let .substitution(playerIn, playerOut, team):
      let who: String
      switch (playerIn.map(DarkGlassFormat.displayName), playerOut.map(DarkGlassFormat.displayName)) {
      case let (on?, off?): who = "\(on) on for \(off)"
      case let (on?, nil): who = "\(on) on"
      case let (nil, off?): who = "\(off) off"
      case (nil, nil): who = "Substitution"
      }
      return "🔁 \(who) · \(code(team))\(at)"
    case let .shotOnTarget(team, total):
      return "🎯 Shot on target · \(code(team)) (\(total))"
    default:
      return nil
    }
  }

  // MARK: - Internals

  private static func goalDetail(scorer: String?, assist: String?, minute: Int?) -> String? {
    var base: String?
    if let scorer {
      base = minute.map { "\(scorer) \($0)'" } ?? scorer
    } else if let minute {
      base = "\(minute)'"
    }
    if let assist {
      base = base.map { "\($0) · assist \(assist)" } ?? "assist \(assist)"
    }
    return base
  }

  private static func varHeadline(_ outcome: VarOutcome) -> String {
    switch outcome {
    case .goalOverturned: return "VAR: GOAL OVERTURNED"
    case .goalStands: return "VAR: GOAL STANDS"
    case .goalAwarded: return "VAR: GOAL AWARDED"
    case .penaltyCancelled: return "VAR: PEN CANCELLED"
    case .penaltyConfirmed: return "VAR: PEN CONFIRMED"
    case let .other(s): return "VAR: \(s.uppercased())"
    }
  }

  /// Compact clock for non-followed matches; nil when there's nothing to show.
  static func compactClock(status: MatchStatus, elapsed: Int?) -> String? {
    if status == .halfTime { return "HT" }
    if status.isFinished { return "FT" }
    if let elapsed { return "\(elapsed)'" }
    return nil
  }

  enum PositionGroup { case goalkeeper, defender, midfielder, forward }

  private static func positionGroup(of player: LineupPlayer) -> PositionGroup {
    switch player.position?.uppercased() {
    case "G": return .goalkeeper
    case "D": return .defender
    case "M": return .midfielder
    case "F": return .forward
    default:
      // Fall back to the grid row (row 1 = GK, then DEF/MID/FWD).
      if let row = player.grid?.split(separator: ":").first, let n = Int(row) {
        switch n {
        case ...1: return .goalkeeper
        case 2: return .defender
        case 3: return .midfielder
        default: return .forward
        }
      }
      return .midfielder
    }
  }

  private static func surname(of name: String) -> String {
    name.split(separator: " ").last.map(String.init) ?? name
  }
}
