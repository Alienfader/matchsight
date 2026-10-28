import Foundation

/// Text the phone read in a glasses photo, weighted by how likely it is to be
/// the shirt the fan is looking at (bigger and nearer the centre = heavier).
public struct NumberCandidate: Sendable, Equatable {
  public var text: String
  public var weight: Double

  public init(text: String, weight: Double) {
    self.text = text
    self.weight = weight
  }
}

/// Look at a player: "who's this?" plus one glasses photo. The phone reads
/// the shirt numbers on the device; this decides which starter, if any, they
/// belong to. It only ever names someone in the starting XIs, so it can't
/// invent a player.
public enum ShirtNumberLookup {
  public enum Result: Sendable, Equatable {
    /// `index` is the player's place in that team's starting XI.
    case player(name: String, teamId: Int, index: Int)
    /// Both teams have a starter wearing it.
    case ambiguous(number: Int, names: [String])
    case notInLineup(number: Int)
    case noNumber
  }

  public static func find(_ candidates: [NumberCandidate], in lineups: [Lineup]) -> Result {
    let numbers = candidates
      .compactMap { c in shirtNumber(c.text).map { ($0, c.weight) } }
      .sorted { $0.1 > $1.1 }
      .map(\.0)
    guard let first = numbers.first else { return .noNumber }
    // The heaviest number someone actually wears; else say the heaviest one.
    for number in numbers {
      let wearers = lineups.flatMap { lineup in
        lineup.startXI.enumerated()
          .filter { $0.element.number == number }
          .map { (name: $0.element.name, teamId: lineup.team.id, index: $0.offset) }
      }
      if wearers.count == 1, let w = wearers.first {
        return .player(name: w.name, teamId: w.teamId, index: w.index)
      }
      if wearers.count > 1 { return .ambiguous(number: number, names: wearers.map(\.name)) }
    }
    return .notInLineup(number: first)
  }

  /// 1…99 written alone; clocks ("27:14"), scores ("1-1") and words don't count.
  static func shirtNumber(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...2).contains(t.count), t.allSatisfy(\.isASCII), t.allSatisfy(\.isNumber),
          let n = Int(t), (1...99).contains(n) else { return nil }
    return n
  }

  /// "Who's this?", "who is that player", "which player is this"… The whole
  /// question has to be the phrase, so "who is this team's captain" is still
  /// an ordinary question for Muse Spark.
  public static func isLookRequest(_ transcript: String) -> Bool {
    let words = transcript.lowercased()
      .replacingOccurrences(of: "’", with: "'")
      .replacingOccurrences(of: "who's", with: "who is")
      .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
      .filter { !$0.isEmpty }
    let phrase = words.joined(separator: " ")
    // "how is this" and a bare "this" are how the transcriber hears a quick
    // "who's this?"; neither is a match question worth sending on.
    let pattern = #"^((who|how|which player) (is )?)?(this|that)( player| guy| one)?$"#
    return phrase.range(of: pattern, options: .regularExpression) != nil
  }
}
