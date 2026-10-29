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
