import Foundation

/// The sound an alert makes through the glasses' speakers. Other matches'
/// goals stay silent (the toast is enough).
public enum AudioCue: Int, Sendable, Equatable, Comparable {
  case whistle, varCheck, redCard, goal

  public static func `for`(_ moment: MatchMoment) -> AudioCue? {
    switch moment.kind {
    case .goal: return .goal
    case .redCard: return .redCard
    case .penaltyAwarded, .varDecision: return .varCheck
    case .halfTime, .fullTime: return .whistle
    case .otherMatchGoal, .yellowCard, .substitution, .shotOnTarget: return nil
    }
  }

  /// One sound per poll: the most important of what just happened.
  public static func loudest(_ moments: [MatchMoment]) -> AudioCue? {
    moments.compactMap(AudioCue.for).max()
  }

  public static func < (a: AudioCue, b: AudioCue) -> Bool { a.rawValue < b.rawValue }
}

/// What the glasses read aloud for an analyst answer.
public enum SpokenAnswer {
  /// "Title. Body", in sentence case and without emoji; nil for the
  /// "Thinking…" step or an empty answer.
  public static func text(_ c: InsightContent) -> String? {
    guard !c.body.isEmpty else { return nil }
    let title = clean(c.title)
    let body = clean(c.body)
    let spokenTitle = title.isEmpty ? "" : sentenceCase(title) + ". "
    return (spokenTitle + body).trimmingCharacters(in: .whitespaces)
  }

  private static func clean(_ s: String) -> String {
    // Digits and # count as emoji too, so only drop pictographs (and their
    // variation selector).
    let kept = s.unicodeScalars.filter { u in
      let p = u.properties
      return !(p.isEmojiPresentation || (p.isEmoji && u.value > 0xFF) || u.value == 0xFE0F)
    }
    return String(String.UnicodeScalarView(kept))
      .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
  }

  /// Titles arrive in capitals for the glasses; read them as a sentence.
  private static func sentenceCase(_ s: String) -> String {
    guard s == s.uppercased() else { return s }
    let lower = s.lowercased()
    return lower.prefix(1).uppercased() + lower.dropFirst()
  }
}

/// The goal call read after the chime, like a commentator: who scored, when,
/// and who leads. Only feed facts; a fact the feed lacks is left out.
public enum GoalCall {
  public static func text(_ moment: MatchMoment, home: Team, away: Team) -> String? {
    guard case let .goal(scorer, _, detail) = moment.kind, detail != .missedPenalty else { return nil }
    var who = [String]()
    if let scorer, !scorer.isEmpty { who.append(surname(scorer)) }
    if detail == .penalty, !who.isEmpty { who.append("from the penalty spot") }
    if let minute = moment.minute { who.append("\(minute) minutes") }
    let opener = detail == .ownGoal ? "Own goal!" : "Goal!"
    let call = who.isEmpty ? opener : "\(opener) \(who.joined(separator: ", "))."
    return "\(call) \(standing(moment.score, home: home, away: away))"
  }

  private static func standing(_ s: ScoreLine, home: Team, away: Team) -> String {
    if s.home == s.away { return "All square, \(spoken(s.home)) all." }
    let (leader, high, low) = s.home > s.away ? (home, s.home, s.away) : (away, s.away, s.home)
    return "\(leader.name) lead \(spoken(high)) \(low == 0 ? "nil" : spoken(low))."
  }

  private static func spoken(_ n: Int) -> String {
    let words = ["nil", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    return words.indices.contains(n) ? words[n] : "\(n)"
  }

  /// "B. Fernandes" → "Fernandes"; one-word and full names stay as they are.
  private static func surname(_ name: String) -> String {
    let parts = name.split(separator: " ")
    guard parts.count > 1, let first = parts.first, first.hasSuffix("."), first.count <= 3 else { return name }
    return parts.dropFirst().joined(separator: " ")
  }
}
