import Foundation

/// Text for the redesigned takeover banner: one calm word or phrase in place
/// of the shouted headline, and the detail line split into its parts.
public enum BannerFormat {
  /// "GOOOAAALL! ⚽" → "Goal", "🟥 SENT OFF" → "Sent off",
  /// "VAR: GOAL STANDS" → "VAR: goal stands", "PEN to ARS" → "Penalty, ARS".
  public static func title(_ headline: String) -> String {
    let words = headline
      .components(separatedBy: .whitespaces)
      .map { $0.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: ":-")).inverted) }
      .filter { !$0.isEmpty }
    guard let first = words.first else { return headline }
    if words.count == 1, first.range(of: "^GO+A+L+$", options: .regularExpression) != nil { return "Goal" }
    if first == "PEN", words.count == 3, words[1] == "to" { return "Penalty, \(words[2])" }
    if first == "VAR:" {
      return (["VAR:"] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }
    let lowered = words.joined(separator: " ").lowercased()
    return lowered.prefix(1).uppercased() + lowered.dropFirst()
  }

  /// "Estêvão 28' · assist M. Gusto" → ("Estêvão", "28′", "assist M. Gusto").
  public static func detail(_ text: String) -> (who: String, minute: String?, rest: String?) {
    let parts = text.components(separatedBy: " · ")
    let rest = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
    let head = parts[0]
    if let range = head.range(of: #"\s(\d+(\+\d+)?)'$"#, options: .regularExpression) {
      let minute = head[range].trimmingCharacters(in: .whitespaces).dropLast() + "′"
      return (String(head[..<range.lowerBound]), String(minute), rest)
    }
    return (head, nil, rest)
  }
}

/// Reads the deck's text lines back into parts for the redesigned pages.
public enum DeckFormat {
  /// "ON TGT  9 · 7" → ("On target", "9", "7"); nil for any other line.
  public static func statRow(_ line: String) -> (label: String, home: String, away: String)? {
    let parts = line.components(separatedBy: "  ").filter { !$0.isEmpty }
    guard parts.count == 2 else { return nil }
    let sides = parts[1].components(separatedBy: " · ")
    guard sides.count == 2 else { return nil }
    let labels = ["SHOTS": "Shots", "ON TGT": "On target", "CORNERS": "Corners", "CARDS": "Cards", "xG": "xG"]
    let label = labels[parts[0]] ?? parts[0].prefix(1).uppercased() + parts[0].dropFirst().lowercased()
    return (label, sides[0], sides[1])
  }

  /// "POSS  ▮▮▮▯▯  55%" → 55.
  public static func possession(_ line: String) -> Int? {
    guard line.hasPrefix("POSS"), line.hasSuffix("%") else { return nil }
    return line.components(separatedBy: " ").last.flatMap { Int($0.dropLast()) }
  }

  /// "LIV 2·0 MCI · 50'" → ("LIV", "2", "0", "MCI", "50′").
  public static func otherLive(_ line: String)
    -> (home: String, homeGoals: String, awayGoals: String, away: String, clock: String?)? {
    let pattern = #"^(\S+) (\d+)·(\d+) (\S+)(?: · (.+))?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
    func group(_ i: Int) -> String? { Range(m.range(at: i), in: line).map { String(line[$0]) } }
    guard let h = group(1), let hg = group(2), let ag = group(3), let a = group(4) else { return nil }
    return (h, hg, ag, a, group(5).map { $0.replacingOccurrences(of: "'", with: "′") })
  }

  /// The home side's share of the momentum events; even when there are none.
  public static func share(home: Int, away: Int) -> Double {
    home + away == 0 ? 0.5 : Double(home) / Double(home + away)
  }
}
