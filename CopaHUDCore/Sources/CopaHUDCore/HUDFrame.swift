import Foundation

// The HUD contract: HUDComposer (core, pure, unit-tested) emits HUDFrame values;
// the app-side HUDBuilder maps a frame to ONE MWDATDisplay layout with exactly
// one tap target. Keeping frames as plain data is what makes the glasses UI
// testable without hardware.

/// One event on the score panel's match timeline bar.
public struct TimelineMarker: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case goal, yellowCard, redCard, varCheck }
  public enum Side: Sendable, Equatable { case home, away }
  public var minute: Int
  public var kind: Kind
  public var side: Side

  public init(minute: Int, kind: Kind, side: Side) {
    self.minute = minute
    self.kind = kind
    self.side = side
  }

  /// Position along the bar, 0…1. The bar spans 90 minutes, stretching to the
  /// elapsed minute once stoppage time runs past it.
  public static func fraction(minute: Int, elapsed: Int?) -> Double {
    let span = Double(max(90, elapsed ?? 90))
    return min(1, max(0, Double(minute) / span))
  }
}

/// Ambient score panel content, fully formatted for display.
public struct PanelContent: Sendable, Equatable {
  public var homeFlag: String      // "🇧🇷"
  public var homeCode: String      // "BRA"
  public var awayFlag: String
  public var awayCode: String
  public var score: ScoreLine
  /// Formatted clock: "67'", "45+2'", "HT", "FT", or kickoff time "19:00".
  public var clock: String
  public var groupLabel: String?
  public var possessionHome: Int?  // 0–100
  /// True when data is older than the staleness threshold — panel shows "· stale ·".
  public var isStale: Bool
  /// True while cinema mode (3-pinch) suppresses alerts — panel shows 🔕.
  public var alertsPaused: Bool
  /// Club crests (nil for national teams or when the feed has no logo).
  public var homeCrestURL: URL?
  public var awayCrestURL: URL?
  /// Match minute for the timeline's progress knob (nil before kickoff).
  public var elapsedMinutes: Int?
  /// Goals, cards and VAR checks in minute order, for the timeline bar.
  public var timeline: [TimelineMarker]
  /// Before kickoff the panel is the pre-match capsule (date, prediction).
  public var isPreMatch: Bool
  public var kickoff: Date?
  public var prediction: WinProbability?

  /// The away side's share, for the two-sided "72% ▮▮▮▮▮▮▮▯▯▯ 28%" row.
  public var possessionAway: Int? { possessionHome.map { 100 - min(100, max(0, $0)) } }

  /// "🇧🇷 BRA 1 · 0 ARG 🇦🇷" for nations, "ARS 1 · 0 CHE" for clubs.
  public var scoreText: String {
    "\(HUDFormat.flagged(homeFlag, homeCode)) \(score.home) · \(score.away) \(HUDFormat.flagged(awayCode, awayFlag))"
  }

  public init(homeFlag: String, homeCode: String, awayFlag: String, awayCode: String,
              score: ScoreLine, clock: String, groupLabel: String?,
              possessionHome: Int?, isStale: Bool, alertsPaused: Bool,
              homeCrestURL: URL? = nil, awayCrestURL: URL? = nil,
              elapsedMinutes: Int? = nil, timeline: [TimelineMarker] = [],
              isPreMatch: Bool = false, kickoff: Date? = nil, prediction: WinProbability? = nil) {
    self.isPreMatch = isPreMatch
    self.kickoff = kickoff
    self.prediction = prediction
    self.elapsedMinutes = elapsedMinutes
    self.timeline = timeline
    self.homeCrestURL = homeCrestURL
    self.awayCrestURL = awayCrestURL
    self.homeFlag = homeFlag
    self.homeCode = homeCode
    self.awayFlag = awayFlag
    self.awayCode = awayCode
    self.score = score
    self.clock = clock
    self.groupLabel = groupLabel
    self.possessionHome = possessionHome
    self.isStale = isStale
    self.alertsPaused = alertsPaused
  }
}

/// Big-energy takeover banner (goal, red card, VAR, HT/FT).
public struct TakeoverContent: Sendable, Equatable {
  public var headline: String      // "GOOOAAALL! ⚽"
  public var scoreLine: String     // "🇧🇷 BRA 2 · 1 ARG 🇦🇷"
  public var detail: String?       // "Neymar 67' · assist Vinícius Júnior"
  /// HTTPS headshot of the protagonist (scorer / sent-off player), when known.
  public var imageURL: String?

  public init(headline: String, scoreLine: String, detail: String?,
              imageURL: String? = nil) {
    self.headline = headline
    self.scoreLine = scoreLine
    self.detail = detail
    self.imageURL = imageURL
  }
}

/// One team's lineup deck page. Doubles as the STARTING XI **index card**:
/// the first card of the carousel shows the whole XI grouped by position,
/// the coach, and a pinch hint before drilling into per-player cards.
public struct LineupContent: Sendable, Equatable {
  public var title: String         // "🇧🇷 Brazil · 4-2-3-1"
  public var rows: [String]        // formatted XI rows
  public var coachLine: String?    // "COACH Dorival"
  public var footer: String?       // "11 players · pinch ›"

  public init(title: String, rows: [String],
              coachLine: String? = nil, footer: String? = nil) {
    self.title = title
    self.rows = rows
    self.coachLine = coachLine
    self.footer = footer
  }
}

/// STARTING XI carousel card — one player at a time, like the Champions
/// League demo: face on the left, light first name over bold surname,
/// "#7 · FWD" line, compact dot strip + "n/11" counter in the footer.
/// 1 pinch advances to the next card (the band exposes no swipe in
/// DAT 0.7.0; tap-forward is the honest mapping).
public struct PlayerCardContent: Sendable, Equatable {
  public var teamLine: String      // "🇧🇷 Brazil · 4-2-3-1"
  public var firstName: String     // "" when the feed gives one name
  public var lastName: String      // "Safonov"
  public var number: String        // "39" or "–"
  public var positionLabel: String? // "GK" / "DEF" / "MID" / "FWD"
  public var photoURL: String?
  public var dots: String          // "○○●○○○○○○○○" position in the XI
  public var counter: String       // "3/11"
  /// Pinch opened this player's detail card (match stats in full).
  public var isDetail: Bool

  public init(teamLine: String, firstName: String, lastName: String,
              number: String, positionLabel: String? = nil,
              photoURL: String?, dots: String, counter: String = "", isDetail: Bool = false) {
    self.teamLine = teamLine
    self.firstName = firstName
    self.lastName = lastName
    self.number = number
    self.positionLabel = positionLabel
    self.photoURL = photoURL
    self.dots = dots
    self.counter = counter
    self.isDetail = isDetail
  }
}

/// One line of a player's detail card: "Passes" · "24 (20 accurate)".
public struct PlayerStatRow: Sendable, Equatable {
  public var label: String
  public var value: String

  public init(label: String, value: String) {
    self.label = label
    self.value = value
  }
}

/// AI Insight deck page: a validated insight, fully formatted for display.
/// The footer says honestly where it came from ("Muse Spark · inferred",
/// "Data only", "Mock AI · scripted").
public struct InsightContent: Sendable, Equatable {
  public var title: String
  public var body: String
  public var footer: String
  /// The fan's spoken question as transcribed ("who is Timber?"), shown
  /// above the answer so a mishearing is obvious. Nil for presets and auto.
  public var question: String?

  public init(title: String, body: String, footer: String, question: String? = nil) {
    self.title = title
    self.body = body
    self.footer = footer
    self.question = question
  }
}

/// Crest intro: both crests large, "ARS v CHE", the competition.
public struct IntroContent: Sendable, Equatable {
  public var homeCode: String
  public var awayCode: String
  public var homeCrestURL: URL?
  public var awayCrestURL: URL?
  /// Flags for national teams; "" for clubs.
  public var homeFlag: String
  public var awayFlag: String
  /// The league, e.g. "Premier League" (else the snapshot's round label).
  public var competition: String?

  public init(homeCode: String, awayCode: String, homeCrestURL: URL?, awayCrestURL: URL?,
              homeFlag: String, awayFlag: String, competition: String?) {
    self.homeCode = homeCode
    self.awayCode = awayCode
    self.homeCrestURL = homeCrestURL
    self.awayCrestURL = awayCrestURL
    self.homeFlag = homeFlag
    self.awayFlag = awayFlag
    self.competition = competition
  }
}

/// One page of the first-run gesture guide.
public struct GuideContent: Sendable, Equatable {
  public var step: Int
  public var total: Int
  /// What to do: "Swipe right".
  public var action: String
  /// What it does in the app: "Next page".
  public var result: String
  /// SF Symbol for the gesture.
  public var icon: String
  /// The last gesture wasn't the one asked for.
  public var tryAgain: Bool

  public init(step: Int, total: Int, action: String, result: String, icon: String, tryAgain: Bool) {
    self.step = step
    self.total = total
    self.action = action
    self.result = result
    self.icon = icon
    self.tryAgain = tryAgain
  }
}

/// The gestures the guide teaches, in order.
public enum GestureGuide {
  public struct Step: Sendable {
    public let action: String
    public let result: String
    public let icon: String
    /// The gesture that completes the step; nil for pinch-and-hold, which
    /// the app reports with `guideHoldDone()`.
    public let expects: HUDInput?
  }

  public static let steps: [Step] = [
    Step(action: "Swipe right", result: "Next page", icon: "arrow.right", expects: .next),
    Step(action: "Swipe left", result: "Back a page, or back a player", icon: "arrow.left", expects: .previous),
    Step(action: "Swipe up", result: "Home: the score", icon: "arrow.up", expects: .home),
    Step(action: "Swipe down", result: "The AI insight on this match", icon: "arrow.down", expects: .insight),
    Step(action: "Pinch", result: "Open a player's card", icon: "hand.pinch", expects: .select),
    Step(action: "Pinch and hold", result: "Ask a question out loud, then let go", icon: "mic", expects: nil),
  ]
}

/// Battery saver's quiet page: one dim score line and the clock, on black.
public struct QuietContent: Sendable, Equatable {
  /// "BRA 1 · 0 ARG"; nil when no match is followed.
  public var scoreLine: String?
  public var clock: String

  public init(scoreLine: String?, clock: String) {
    self.scoreLine = scoreLine
    self.clock = clock
  }
}

/// Where the current page sits in the deck, for the page dots. `pulse` is
/// true just after a gesture arrived, so the fan can tell a gesture the band
/// never sent from one the app ignored.
public struct DeckPosition: Sendable, Equatable {
  public var index: Int
  public var count: Int
  public var pulse: Bool

  public init(index: Int, count: Int, pulse: Bool) {
    self.index = index
    self.count = count
    self.pulse = pulse
  }
}

/// Everything the glasses should currently show. One frame == one display.send.
public struct HUDFrame: Sendable, Equatable {
  public enum Body: Sendable, Equatable {
    case panel(PanelContent)
    case events(title: String, lines: [String])   // newest first
    case lineup(LineupContent)
    case playerCard(PlayerCardContent)            // STARTING XI carousel
    case stats(title: String, lines: [String])    // formatted stat bars/rows
    case otherLive(title: String, lines: [String])
    /// AI Match Analyst insight (deck page right after the panel).
    case insight(InsightContent)
    case takeover(TakeoverContent)
    /// Crest intro shown when a new match is followed.
    case intro(IntroContent)
    /// Idle / pre-kickoff / error text.
    case message(String)
    /// Battery saver: the fan hasn't touched the band for a while.
    case quiet(QuietContent)
    /// First-run gesture guide.
    case guide(GuideContent)
  }

  public var body: Body
  /// Cross-match toast line overlaying the body, e.g. "⚽ FRA 2·0 GER · Mbappé 84'".
  public var toast: String?
  /// Page dots; nil while a takeover or the crest intro covers the deck.
  public var deck: DeckPosition?
  /// Battery saver (display off): the app turns the glasses display off
  /// until a frame arrives with this false again.
  public var displayOff: Bool

  public init(body: Body, toast: String? = nil, deck: DeckPosition? = nil, displayOff: Bool = false) {
    self.body = body
    self.toast = toast
    self.deck = deck
    self.displayOff = displayOff
  }
}

/// A resolved Neural Band gesture (DAT 1.0 Inputs), mapped by the app from
/// raw select / nav events.
public enum HUDInput: Sendable, Equatable {
  case next, previous, home, insight
  /// Pinch: opens / closes a player's detail card in the lineup carousel,
  /// otherwise the same as `next`.
  case select
}

/// What the glasses do after a quiet spell with no gestures and nothing
/// happening in the match.
public enum BatterySaver: String, CaseIterable, Sendable {
  /// Always show the full page.
  case off
  /// Drop to a near-black page with just the score and clock.
  case dim
  /// Turn the display off; goals, cards and gestures turn it back on.
  case displayOff
}

/// User-tunable HUD behaviour (Settings).
public struct HUDConfig: Sendable, Equatable {
  public var takeoverSeconds: TimeInterval
  public var toastSeconds: TimeInterval
  public var toastsEnabled: Bool
  public var batterySaver: BatterySaver
  /// The quiet spell before battery saver steps in.
  public var idleSeconds: TimeInterval
  /// Yellow cards, substitutions and shots on target as toasts.
  public var minorNotices: Bool

  public init(takeoverSeconds: TimeInterval = 8,
              toastSeconds: TimeInterval = 5,
              toastsEnabled: Bool = true,
              batterySaver: BatterySaver = .off,
              idleSeconds: TimeInterval = 20,
              minorNotices: Bool = true) {
    self.takeoverSeconds = takeoverSeconds
    self.toastSeconds = toastSeconds
    self.toastsEnabled = toastsEnabled
    self.batterySaver = batterySaver
    self.idleSeconds = idleSeconds
    self.minorNotices = minorNotices
  }
}
