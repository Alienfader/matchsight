import Foundation

/// FIFA trigram + flag emoji for the likely 2026 World Cup nations.
///
/// Matching is case-insensitive and trims surrounding whitespace; common feed
/// name variants are aliased (e.g. "Korea Republic" → KOR). Unknown names
/// (dev/club fixtures) fall back to the first three letters uppercased + 🏳️ so
/// the HUD never crashes and never shows a wrong flag.
public enum NationStyle {
  public typealias Style = (code: String, flag: String)

  /// Number of distinct nations in the table (excluding aliases). Sanity-checked
  /// by tests against the 48-team field.
  public static var nationCount: Int { table.count }

  /// The nation's style, or nil when the name isn't a known national team.
  public static func known(_ teamName: String) -> Style? {
    let key = teamName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let canonical = aliases[key], let s = table[canonical] {
      return s
    }
    return table[key]
  }

  public static func style(for teamName: String) -> Style {
    if let s = known(teamName) { return s }
    let code = String(teamName.trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(3)).uppercased()
    return (code, "🏳️")
  }

  // Canonical lookup keyed by lowercased nation name.
  private static let table: [String: Style] = [
    // Hosts
    "usa": ("USA", "🇺🇸"),
    "mexico": ("MEX", "🇲🇽"),
    "canada": ("CAN", "🇨🇦"),
    // South America
    "brazil": ("BRA", "🇧🇷"),
    "argentina": ("ARG", "🇦🇷"),
    "uruguay": ("URU", "🇺🇾"),
    "colombia": ("COL", "🇨🇴"),
    "ecuador": ("ECU", "🇪🇨"),
    "paraguay": ("PAR", "🇵🇾"),
    "peru": ("PER", "🇵🇪"),
    "chile": ("CHI", "🇨🇱"),
    "venezuela": ("VEN", "🇻🇪"),
    // Europe
    "france": ("FRA", "🇫🇷"),
    "england": ("ENG", "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"),
    "wales": ("WAL", "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"),
    "scotland": ("SCO", "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"),
    "spain": ("ESP", "🇪🇸"),
    "germany": ("GER", "🇩🇪"),
    "portugal": ("POR", "🇵🇹"),
    "netherlands": ("NED", "🇳🇱"),
    "belgium": ("BEL", "🇧🇪"),
    "italy": ("ITA", "🇮🇹"),
    "croatia": ("CRO", "🇭🇷"),
    "switzerland": ("SUI", "🇨🇭"),
    "denmark": ("DEN", "🇩🇰"),
    "poland": ("POL", "🇵🇱"),
    "serbia": ("SRB", "🇷🇸"),
    "austria": ("AUT", "🇦🇹"),
    "czechia": ("CZE", "🇨🇿"),
    "turkey": ("TUR", "🇹🇷"),
    "ukraine": ("UKR", "🇺🇦"),
    "norway": ("NOR", "🇳🇴"),
    "sweden": ("SWE", "🇸🇪"),
    "hungary": ("HUN", "🇭🇺"),
    "romania": ("ROU", "🇷🇴"),
    "greece": ("GRE", "🇬🇷"),
    // Africa
    "morocco": ("MAR", "🇲🇦"),
    "senegal": ("SEN", "🇸🇳"),
    "tunisia": ("TUN", "🇹🇳"),
    "ghana": ("GHA", "🇬🇭"),
    "cameroon": ("CMR", "🇨🇲"),
    "nigeria": ("NGA", "🇳🇬"),
    "egypt": ("EGY", "🇪🇬"),
    "algeria": ("ALG", "🇩🇿"),
    "mali": ("MLI", "🇲🇱"),
    "ivory coast": ("CIV", "🇨🇮"),
    "south africa": ("RSA", "🇿🇦"),
    // Asia / Oceania
    "japan": ("JPN", "🇯🇵"),
    "south korea": ("KOR", "🇰🇷"),
    "saudi arabia": ("KSA", "🇸🇦"),
    "iran": ("IRN", "🇮🇷"),
    "australia": ("AUS", "🇦🇺"),
    "qatar": ("QAT", "🇶🇦"),
    "uzbekistan": ("UZB", "🇺🇿"),
    "jordan": ("JOR", "🇯🇴"),
    "iraq": ("IRQ", "🇮🇶"),
    "new zealand": ("NZL", "🇳🇿"),
    // CONCACAF
    "costa rica": ("CRC", "🇨🇷"),
    "panama": ("PAN", "🇵🇦"),
    "jamaica": ("JAM", "🇯🇲"),
    "honduras": ("HON", "🇭🇳"),
  ]

  // Feed name variants → canonical table key (both lowercased).
  private static let aliases: [String: String] = [
    "united states": "usa",
    "united states of america": "usa",
    "korea republic": "south korea",
    "republic of korea": "south korea",
    "côte d'ivoire": "ivory coast",
    "cote d'ivoire": "ivory coast",
    "czech republic": "czechia",
    "türkiye": "turkey",
    "turkiye": "turkey",
    "ir iran": "iran",
    "holland": "netherlands",
  ]
}
