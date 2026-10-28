import Foundation

// Pure, fully unit-tested HUD state machine. No clocks, no I/O: every
// time-dependent method takes an injected `now`. The app calls
// tick(now:) then frame(now:) ~1Hz and renders the frame via HUDBuilder.

/// Pure HUD state machine: holds the deck (Panel → AI Insight → Events →
/// Lineup home → Lineup away → Stats → Other Live → wrap), plays queued takeovers sequentially,
/// overlays toasts, and resolves the tap-burst vocabulary
/// (1 = next page · 2 = home · 3+ = pause/resume alerts).
public struct HUDComposer: Sendable {
  public private(set) var alertsPaused: Bool = false

  private var config: HUDConfig

  /// Deck pages in pinch order (wraps). The AI insight sits one pinch from
  /// the panel so it's always a single gesture away.
  private enum DeckPage: Int, CaseIterable, Sendable {
    case panel, insight, events, lineupHome, lineupAway, stats, otherLive

    var next: DeckPage {
      DeckPage(rawValue: (rawValue + 1) % DeckPage.allCases.count)!
    }

    var previous: DeckPage {
      let n = DeckPage.allCases.count
      return DeckPage(rawValue: (rawValue + n - 1) % n)!
    }
  }

  private var page: DeckPage = .panel
  private var prediction: WinProbability?
  /// Card position within a lineup page's STARTING XI carousel. Slot 0 is
  /// the roster index card; slots 1…n are the player cards. Reset whenever
  /// the page changes.
  private var playerIndex: Int = 0 {
    didSet { if playerIndex == 0 { playerDetail = false } }
  }
  /// The focused player card shows the detail (full match stats). Closed
  /// whenever the carousel returns to the roster index or the page changes.
  private var playerDetail = false

  // Deck data (replaced wholesale on each poll).
  private var followed: MatchSnapshot?
  private var events: [MatchEvent] = []
  private var lineups: [Lineup] = []
  private var others: [MatchSnapshot] = []
  private var stats: MatchStats?
  private var isStale: Bool = false
  /// Latest AI insight for the insight page (nil → "warming up").
  private var insight: InsightContent?
  /// Push-to-talk banner ("🎙 Listening…"); overrides the toast while set.
  private var listening: String?

  // Clock interpolation.
  private var followedReceivedAt: Date = .distantPast
  private var clockFloorMinute: Int = 0

  // Takeover queue (followed-match moments) + the one currently holding.
  private var takeoverQueue: [MatchMoment] = []
  private var currentTakeover: TakeoverContent?
  private var takeoverDeadline: Date?

  // Crest intro for a newly followed match (below takeovers, above the deck).
  private var intro: IntroContent?
  private var introDeadline: Date?
  private var introducedFixtureId: Int?
  /// The followed fixture's league (e.g. "Premier League") for the pill and
  /// intro; live snapshots only carry the round, which is the fallback.
  private var competition: String?

  // Single newest toast.
  private var currentToast: String?
  private var toastDeadline: Date?

  public init(config: HUDConfig = HUDConfig()) {
    self.config = config
  }

  /// Update tunable behaviour (Settings changed).
  public mutating func setConfig(_ config: HUDConfig) {
    self.config = config
  }

  // MARK: - Ingest

  /// Replace the data the deck renders from. Called after every poll cycle.
  public mutating func update(followed: MatchSnapshot?,
                              events: [MatchEvent],
                              lineups: [Lineup],
                              others: [MatchSnapshot],
                              stats: MatchStats? = nil,
                              isStale: Bool,
                              now: Date) {
    if let f = followed {
      if f.fixtureId != self.followed?.fixtureId { clockFloorMinute = 0 }
      self.followed = f
      self.followedReceivedAt = now
    } else {
      self.followed = nil
    }
    self.events = events
    self.lineups = lineups
    self.others = others
    self.stats = stats
    self.isStale = isStale
    bumpClockFloor(now: now)
  }

  /// Queue moments for presentation (takeovers for the followed match,
  /// toasts for other matches). Dropped silently while alertsPaused.
  public mutating func enqueue(_ moments: [MatchMoment], now: Date) {
    guard !alertsPaused else { return }
    for moment in moments {
      if case let .otherMatchGoal(snapshot, scorer) = moment.kind {
        guard config.toastsEnabled else { continue }
        currentToast = HUDFormat.toastLine(snapshot: snapshot, scorer: scorer, minute: moment.minute)
        toastDeadline = now.addingTimeInterval(config.toastSeconds)
      } else {
        takeoverQueue.append(moment)
      }
    }
    startTakeoverIfIdle(now: now)
  }

  /// Show the crest intro for the followed match. The app calls this when a
  /// new match becomes followed; it never repeats for the same fixture, and
  /// is skipped in cinema mode or for a match that has already finished.
  public mutating func showMatchIntro(now: Date) {
    guard let f = followed, f.fixtureId != introducedFixtureId,
          !alertsPaused, !f.status.isFinished else { return }
    introducedFixtureId = f.fixtureId
    let h = TeamStyle.style(for: f.home)
    let a = TeamStyle.style(for: f.away)
    intro = IntroContent(homeCode: h.code, awayCode: a.code,
                         homeCrestURL: h.crestURL, awayCrestURL: a.crestURL,
                         homeFlag: h.flag, awayFlag: a.flag, competition: competition ?? f.groupLabel)
    introDeadline = now.addingTimeInterval(config.takeoverSeconds)
  }

  public mutating func setCompetition(_ competition: String?) {
    self.competition = competition
  }

  private mutating func dismissIntro() {
    intro = nil
    introDeadline = nil
  }

  /// Swipe-back gesture: step the STARTING XI carousel one player backward.
  /// Only acts on lineup pages that have a loaded XI; ignored everywhere else.
  public mutating func handleCarouselBack() {
    guard carouselXI() != nil, playerIndex > 0 else { return }
    playerIndex -= 1
  }

  /// Whether a goal/red-card takeover is currently showing.
  public var hasTakeover: Bool { currentTakeover != nil }

  /// The followed match's pre-match prediction (nil to clear).
  public mutating func setPrediction(_ value: WinProbability?) { prediction = value }

  /// Immediately clears the active takeover AND drains the entire queue.
  /// Used by the phone-side "skip" gesture so the user doesn't have to
  /// double-tap once per queued goal during a busy demo.
  public mutating func clearAllTakeovers() {
    currentTakeover = nil
    takeoverDeadline = nil
    takeoverQueue.removeAll()
  }

  /// Which card in the STARTING XI carousel is currently showing.
  /// Exposed so the phone LiveView can sync its portrait card carousel.
  public var hudPlayerIndex: Int { playerIndex }

  /// The full XI for the page currently displaying, or nil when the HUD
  /// isn't on a lineup page or no lineup has arrived yet.
  public var currentXI: [LineupPlayer]? { carouselXI() }

  /// Team name behind the current lineup page (home or away lineup page),
  /// for the phone carousel header. Nil off lineup pages.
  public var currentXITeam: Team? {
    switch page {
    case .lineupHome: return followed?.home
    case .lineupAway: return followed?.away
    default: return nil
    }
  }

  public var currentXITeamName: String? {
    switch page {
    case .lineupHome: return followed?.home.name
    case .lineupAway: return followed?.away.name
    default: return nil
    }
  }

  // MARK: - AI insight page

  /// Replace the insight page's content. Data only — never moves the page,
  /// so a late answer can't yank the user off whatever they're reading.
  public mutating func setInsight(_ content: InsightContent?) {
    insight = content
  }

  /// Jump to the insight page (phone-side "Ask the analyst").
  public mutating func showInsightPage() {
    page = .insight
    playerIndex = 0
  }

  public var isOnInsightPage: Bool { page == .insight }

  /// Jump directly to a specific player card (phone-side tap on a tile).
  public mutating func goToPlayer(_ index: Int) {
    guard let xi = carouselXI(), index < xi.count else { return }
    playerIndex = index
  }

  // MARK: - Neural Band input (DAT 1.0 Inputs)

  /// A resolved Neural Band gesture: pinch / swipe right = next, swipe left =
  /// previous, swipe up = home.
  public mutating func handle(_ input: HUDInput, now: Date) {
    // Any gesture dismisses the intro and acts as usual.
    dismissIntro()
    switch input {
    case .next:
      handleTapBurst(count: 1, now: now)
    case .previous:
      // Mid-carousel: step back one card (to the roster index at most);
      // otherwise the previous deck page. Acts on the deck under a takeover.
      if carouselXI() != nil, playerIndex > 0 {
        playerIndex -= 1
      } else {
        page = page.previous
        playerIndex = 0
      }
    case .home:
      page = .panel
      playerIndex = 0
      dismissTakeover(now: now)
    case .insight:
      page = .insight
      playerIndex = 0
      dismissTakeover(now: now)
    case .select:
      if carouselXI() != nil, playerIndex > 0 {
        playerDetail.toggle()
      } else {
        handleTapBurst(count: 1, now: now)
      }
    }
  }

  /// Drop the takeover on screen; the next queued one (if any) starts.
  private mutating func dismissTakeover(now: Date) {
    guard currentTakeover != nil else { return }
    currentTakeover = nil
    takeoverDeadline = nil
    startTakeoverIfIdle(now: now)
  }

  /// Show (or clear with nil) the push-to-talk banner on the glasses.
  public mutating func setListening(_ text: String?) {
    listening = text
  }

  /// Resolved tap burst from the glasses card (count already resolved by the
  /// 350ms window on the phone side).
  public mutating func handleTapBurst(count: Int, now: Date) {
    guard count > 0 else { return }
    switch count {
    case 1:
      // On a lineup page the pinch advances the STARTING XI carousel first
      // (the demo's swipe-forward): index card, then one card per player;
      // past the last player it flows to the next deck page. Everywhere
      // else: next deck page (wrap). Acts on the deck underneath even
      // during a takeover.
      if let xi = carouselXI(), playerIndex < xi.count {
        playerIndex += 1
      } else {
        page = page.next
        playerIndex = 0
      }
    case 2:
      // On a lineup page mid-carousel, double-pinch steps BACK one player —
      // the glasses' only way to reverse through the XI (the hardware has no
      // swipe; FlexBox exposes no long-press). At the first card it falls
      // through to its global meaning: jump home / dismiss a takeover.
      if carouselXI() != nil, playerIndex > 0, currentTakeover == nil {
        playerIndex -= 1
      } else {
        page = .panel
        playerIndex = 0
        if currentTakeover != nil {
          currentTakeover = nil
          takeoverDeadline = nil
          startTakeoverIfIdle(now: now)
        }
      }
    default:
      // 3+ pinches toggle cinema mode.
      alertsPaused.toggle()
    }
  }

  /// Advance time-driven state (takeover/toast expiry). Call before frame().
  public mutating func tick(now: Date) {
    if let deadline = takeoverDeadline, now >= deadline {
      currentTakeover = nil
      takeoverDeadline = nil
      startTakeoverIfIdle(now: now)
    }
    if let deadline = introDeadline, now >= deadline {
      dismissIntro()
    }
    if let deadline = toastDeadline, now >= deadline {
      currentToast = nil
      toastDeadline = nil
    }
    bumpClockFloor(now: now)
  }

  /// The frame the glasses should show right now. Pure read — no expiry here.
  public func frame(now: Date) -> HUDFrame {
    let body: HUDFrame.Body
    if let takeover = currentTakeover {
      body = .takeover(takeover)
    } else if let intro {
      body = .intro(intro)
    } else {
      body = pageBody(now: now)
    }
    return HUDFrame(body: body, toast: listening ?? currentToast)
  }

  // MARK: - Takeovers

  private mutating func startTakeoverIfIdle(now: Date) {
    guard currentTakeover == nil, !takeoverQueue.isEmpty else { return }
    let moment = takeoverQueue.removeFirst()
    let home = followed?.home ?? Team(id: 0, name: "?")
    let away = followed?.away ?? Team(id: 0, name: "?")
    currentTakeover = HUDFormat.takeover(moment: moment, home: home, away: away)
    takeoverDeadline = now.addingTimeInterval(config.takeoverSeconds)
  }

  // MARK: - Clock

  private mutating func bumpClockFloor(now: Date) {
    if let raw = rawLiveMinute(now: now) {
      clockFloorMinute = max(clockFloorMinute, raw)
    }
  }

  /// Interpolated raw minute for an in-progress half, or nil when the status
  /// has no ticking clock (HT/FT/NS/etc.).
  private func rawLiveMinute(now: Date) -> Int? {
    guard let f = followed, let elapsed = f.elapsedMinutes, interpolates(f.status) else { return nil }
    let seconds = max(0, now.timeIntervalSince(followedReceivedAt))
    return elapsed + Int(seconds / 60)
  }

  private func interpolates(_ status: MatchStatus) -> Bool {
    switch status {
    case .firstHalf, .secondHalf, .extraTime, .live: return true
    default: return false
    }
  }

  private func clockString(now: Date) -> String {
    guard let f = followed else { return "" }
    if f.status == .notStarted { return HUDFormat.kickoffTime(f.kickoff) }
    if f.status == .halfTime { return "HT" }
    if f.status.isFinished { return "FT" }
    if let raw = rawLiveMinute(now: now) {
      return HUDFormat.minuteLabel(max(raw, clockFloorMinute), extra: nil)
    }
    // Live but no minute yet (e.g. break time): show status-agnostic placeholder.
    return f.status == .breakTime ? "BREAK" : ""
  }

  // MARK: - Page rendering

  private func pageBody(now: Date) -> HUDFrame.Body {
    switch page {
    case .panel: return panelBody(now: now)
    case .insight: return insightBody()
    case .events: return eventsBody()
    case .lineupHome: return lineupBody(team: followed?.home)
    case .lineupAway: return lineupBody(team: followed?.away)
    case .stats: return statsBody()
    case .otherLive: return otherLiveBody()
    }
  }

  private func insightBody() -> HUDFrame.Body {
    guard followed != nil else { return .message("No match followed") }
    guard let insight else { return .message("AI Analyst warming up…") }
    return .insight(insight)
  }

  private func statsBody() -> HUDFrame.Body {
    let title: String
    if let f = followed {
      let h = TeamStyle.style(for: f.home)
      let a = TeamStyle.style(for: f.away)
      title = "\(h.code) · stats · \(a.code)"
    } else {
      title = "stats"
    }
    guard let stats else {
      return .stats(title: title, lines: ["no stats yet"])
    }
    return .stats(title: title, lines: HUDFormat.statsLines(stats))
  }

  private func panelBody(now: Date) -> HUDFrame.Body {
    guard let f = followed else { return .message("No match followed") }
    let h = TeamStyle.style(for: f.home)
    let a = TeamStyle.style(for: f.away)
    return .panel(PanelContent(
      homeFlag: h.flag, homeCode: h.code, awayFlag: a.flag, awayCode: a.code,
      score: f.score, clock: clockString(now: now), groupLabel: competition ?? f.groupLabel,
      possessionHome: f.possessionHome, isStale: isStale, alertsPaused: alertsPaused,
      homeCrestURL: h.crestURL, awayCrestURL: a.crestURL,
      elapsedMinutes: f.elapsedMinutes, timeline: timeline(home: f.home),
      isPreMatch: f.status == .notStarted, kickoff: f.kickoff, prediction: prediction))
  }

  /// Goals, cards and VAR checks for the panel's timeline bar, by minute.
  private func timeline(home: Team) -> [TimelineMarker] {
    events.sorted { ($0.minute, $0.extraMinute ?? 0) < ($1.minute, $1.extraMinute ?? 0) }
      .compactMap { e in
        let kind: TimelineMarker.Kind
        switch e.kind {
        case .goal(.missedPenalty): return nil
        case .goal: kind = .goal
        case .card(.yellow): kind = .yellowCard
        case .card(.red): kind = .redCard
        case .varDecision: kind = .varCheck
        case .substitution, .unknown: return nil
        }
        return TimelineMarker(minute: e.minute, kind: kind, side: e.team.id == home.id ? .home : .away)
      }
  }

  private func eventsBody() -> HUDFrame.Body {
    let sorted = events.sorted {
      ($0.minute, $0.extraMinute ?? 0) > ($1.minute, $1.extraMinute ?? 0)
    }
    let lines = sorted.prefix(8).map(HUDFormat.eventLine)
    return .events(title: "Events", lines: lines.isEmpty ? ["no events yet"] : Array(lines))
  }

  /// STARTING XI carousel: the roster index card first (whole XI at a
  /// glance), then one demo-style player card per pinch. Falls back to the
  /// honest text page when the feed has no lineup yet.
  private func lineupBody(team: Team?) -> HUDFrame.Body {
    guard let team else {
      return .lineup(LineupContent(title: "Lineup", rows: ["lineup not available"]))
    }
    if let lineup = lineups.first(where: { $0.team.id == team.id }),
       !lineup.startXI.isEmpty {
      if playerIndex == 0 {
        return .lineup(HUDFormat.rosterIndex(lineup))
      }
      let index = min(playerIndex - 1, lineup.startXI.count - 1)
      var card = HUDFormat.playerCard(lineup: lineup, cardIndex: index)
      card.isDetail = playerDetail
      return .playerCard(card)
    }
    let title = HUDFormat.flagged(TeamStyle.style(for: team).flag, team.name)
    return .lineup(LineupContent(title: title, rows: ["lineup not available"]))
  }

  /// The XI behind the current page's carousel, or nil when the page isn't a
  /// lineup page (or has no lineup data).
  private func carouselXI() -> [LineupPlayer]? {
    let team: Team?
    switch page {
    case .lineupHome: team = followed?.home
    case .lineupAway: team = followed?.away
    default: return nil
    }
    guard let team,
          let lineup = lineups.first(where: { $0.team.id == team.id }),
          !lineup.startXI.isEmpty else { return nil }
    return lineup.startXI
  }

  private func otherLiveBody() -> HUDFrame.Body {
    let sorted = others.sorted { ($0.elapsedMinutes ?? -1) > ($1.elapsedMinutes ?? -1) }
    let lines = sorted.map(HUDFormat.otherLiveLine)
    return .otherLive(title: "Other Live",
                      lines: lines.isEmpty ? ["no other matches live"] : lines)
  }
}
