import Foundation

/// How a team is labelled on the HUD: a three-letter code, a flag (national
/// teams only) and a crest (clubs, from the feed's logo URL).
///
/// National teams keep NationStyle's FIFA trigram + flag. Clubs get no flag —
/// the 🏳️ fallback would read as a real (wrong) flag — and use, in order: the
/// API's team code, the curated table below, then the first three letters.
public enum TeamStyle {
  public typealias Style = (code: String, flag: String, crestURL: URL?)

  public static func style(for team: Team) -> Style {
    if let nation = NationStyle.known(team.name) {
      return (nation.code, nation.flag, nil)
    }
    let key = team.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let code = team.code ?? clubCodes[key] ?? fallbackCode(team.name)
    return (code, "", team.logoURL)
  }

  /// "Bodø/Glimt" → "BOD": letters only, diacritics folded.
  static func fallbackCode(_ name: String) -> String {
    let letters = name.folding(options: .diacriticInsensitive, locale: nil).filter(\.isLetter)
    return String(letters.prefix(3)).uppercased()
  }

  /// Keyed by API-Football's lowercased team name. Premier League clubs of
  /// recent seasons plus the Champions League regulars; the API's own `code`
  /// wins whenever the team catalogue supplied one.
  private static let clubCodes: [String: String] = [
    // Premier League
    "arsenal": "ARS", "aston villa": "AST", "bournemouth": "BOU", "brentford": "BRE",
    "brighton": "BRI", "burnley": "BUR", "chelsea": "CHE", "crystal palace": "CRY",
    "everton": "EVE", "fulham": "FUL", "ipswich": "IPS", "leeds": "LEE",
    "leicester": "LEI", "liverpool": "LIV", "luton": "LUT", "manchester city": "MCI",
    "manchester united": "MUN", "newcastle": "NEW", "nottingham forest": "NOT",
    "sheffield utd": "SHU", "southampton": "SOU", "sunderland": "SUN",
    "tottenham": "TOT", "west ham": "WHU", "wolves": "WOL", "norwich": "NOR",
    "watford": "WAT", "middlesbrough": "MID", "coventry": "COV", "hull city": "HUL",
    // Champions League regulars
    "real madrid": "RMA", "barcelona": "BAR", "atletico madrid": "ATM",
    "athletic club": "ATH", "villarreal": "VIL", "bayern münchen": "BAY",
    "borussia dortmund": "BVB", "bayer leverkusen": "B04", "rb leipzig": "RBL",
    "eintracht frankfurt": "SGE", "paris saint germain": "PSG", "monaco": "ASM",
    "marseille": "OM", "lille": "LIL", "inter": "INT", "ac milan": "MIL",
    "juventus": "JUV", "napoli": "NAP", "atalanta": "ATA", "benfica": "BEN",
    "fc porto": "POR", "sporting cp": "SCP", "ajax": "AJA", "psv eindhoven": "PSV",
    "feyenoord": "FEY", "celtic": "CEL", "club brugge kv": "BRU", "galatasaray": "GAL",
  ]
}
