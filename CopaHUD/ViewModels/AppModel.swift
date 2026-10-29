import Foundation
import Observation
import CopaHUDCore

/// The conductor. Owns the feed, the pure `MatchEngine`/`HUDComposer` state
/// machines, the poll loops, and the staleness bookkeeping — and drives the
/// glasses through `GlassesViewModel.render`.
@Observable
@MainActor
final class AppModel {
  // MARK: Dependencies
  @ObservationIgnored private(set) var feed: any MatchFeed
  @ObservationIgnored private var engine = MatchEngine()
  @ObservationIgnored private var composer: HUDComposer
  @ObservationIgnored weak var glasses: GlassesViewModel?
  /// AI Match Analyst: owns every model call (refresh policy, cancellation,
  /// template fallback) so nothing here blocks polling or rendering.
  @ObservationIgnored let insights: InsightCoordinator

  // MARK: Observable state (mirrored by the phone views)
  private(set) var fixtures: [Fixture] = []
  /// Favourites' scheduled matches after today (the Today tab's Coming up).
  private(set) var upcoming: [Fixture] = []
  /// The day picked in the Today tab's day strip (local midnight).
  private(set) var selectedDay = Calendar.current.startOfDay(for: Date())
  /// Fixtures on `selectedDay` when it isn't today; today's list is `fixtures`.
  private(set) var dayFixtures: [Fixture] = []
  private(set) var isLoadingDay = false
  /// Other days' lists, refetched after 10 minutes. Cleared on a feed change.
  @ObservationIgnored private var dayCache: [Date: (fixtures: [Fixture], at: Date)] = [:]
  @ObservationIgnored private var dayTask: Task<Void, Never>?
  private(set) var followedFixtureId: Int?
  /// Newest last. LiveView shows these (reversed for newest-first).
  private(set) var lastMoments: [MatchMoment] = []
  private(set) var frame: HUDFrame = HUDFrame(body: .message("Matchsight — waiting for kickoff"))
  /// Current AI insight + whether it's updating / fell back (LiveView card).
  private(set) var insightState: InsightState = .idle
  /// True once the followed match has data the analyst can use (gates "Ask").
  private(set) var analystReady = false
  /// Ask-by-voice is possible (Meta access configured: proxy or key).
  private(set) var voiceAvailable = false
  /// "Transcribing…", "Heard: …", "Didn't catch that", or a failure line.
  private(set) var voiceStatus: String?
  @ObservationIgnored private var transcriber: (any VoiceTranscriber)?
  /// One recorder for both push-to-talk paths: the phone's mic button and the
  /// glasses' pinch-and-hold.
  let recorder = VoiceRecorder()
  /// The glasses hold's in-flight mic start; the release awaits it.
  @ObservationIgnored private var voiceStart: Task<Void, Never>?
  @ObservationIgnored private var listeningToken = 0
  /// Set on API auth/quota errors → phone banner; glasses stay on last frame.
  private(set) var banner: FeedError?
  /// Every in-progress match right now (followed one included), newest-minute
  /// first. Drives the Today page's LIVE NOW section.
  private(set) var liveNow: [MatchSnapshot] = []
  private(set) var isStale = false
  var alertsPaused: Bool { composer.alertsPaused }

  // MARK: Settings (UserDefaults mirrors; the API key lives in the Keychain)
  private(set) var config: HUDConfig
  private(set) var demoMode: Bool
  /// Keep the mic ready while the glasses are connected, so pinch-and-hold
  /// works with the phone locked (iOS shows the mic indicator meanwhile).
  private(set) var voiceReadyWhenLocked: Bool
  /// Seconds the glasses wait so they never run ahead of the TV picture.
  private(set) var tvDelaySeconds: Double
  /// "Who's this?" takes one glasses photo to read a shirt number (opt-in).
  private(set) var lookAtPlayerEnabled: Bool

  // MARK: Bookkeeping
  @ObservationIgnored private var scheduleTask: Task<Void, Never>?
  @ObservationIgnored private var followedTask: Task<Void, Never>?
  @ObservationIgnored private var othersTask: Task<Void, Never>?
  @ObservationIgnored private var tickTask: Task<Void, Never>?

  @ObservationIgnored private var lineupsFetched = Set<Int>()
  @ObservationIgnored private var halfTimeLineupRefreshed = false
  @ObservationIgnored private var lastSnapshot: MatchSnapshot?
  @ObservationIgnored private var lastEvents: [MatchEvent] = []
  @ObservationIgnored private var lastLineups: [Lineup] = []
  @ObservationIgnored private var lastOthers: [MatchSnapshot] = []
  @ObservationIgnored private var lastStats: MatchStats?
  /// Per-player counters for the glasses' player cards, by player id.
  @ObservationIgnored private(set) var playerStats: [Int: PlayerStats] = [:]
  /// Pre-match win/draw/win percentages for the followed match (one fetch).
  @ObservationIgnored private var lastPrediction: WinProbability?
  @ObservationIgnored private var predictionFetched = Set<Int>()
  @ObservationIgnored private var lastFollowedPollOk: Date?
  /// One followed-match poll, held back by the TV delay before it is shown.
  private struct FollowedUpdate {
    let fixtureId: Int
    let snapshot: MatchSnapshot
    let events: [MatchEvent]
    let stats: MatchStats?
    let playerStats: [Int: PlayerStats]?
  }
  @ObservationIgnored private var tvDelayLine = BroadcastDelay<FollowedUpdate>()
  /// The live clock to the second (Sync with TV), from the undelayed polls.
  @ObservationIgnored private var liveClock = LiveMatchClock()
  /// The latest polled status (ahead of the TV delay), for the poll interval.
  @ObservationIgnored private var lastPolledStatus: MatchStatus?

  /// The fan's favourite clubs (team picker). Drives auto-follow and toasts.
  private(set) var favourites: [Team] = []
  /// What is followed and why (manual vs auto, full-time hold, unfollowed).
  @ObservationIgnored private var followState = FollowState()

  // MARK: Init

  init() {
    let d = UserDefaults.standard
    let takeover = d.object(forKey: Keys.takeoverSeconds) as? Double ?? 8
    let toasts = d.object(forKey: Keys.toastsEnabled) as? Bool ?? true
    let demo = d.bool(forKey: Keys.demoMode)
    // Battery saver defaults to the dim page: it never turns the display off.
    let saver = d.string(forKey: Keys.batterySaver).flatMap(BatterySaver.init(rawValue:)) ?? .dim
    let cfg = HUDConfig(takeoverSeconds: takeover, toastsEnabled: toasts, batterySaver: saver)
    self.config = cfg
    self.demoMode = demo
    self.voiceReadyWhenLocked = d.object(forKey: Keys.voiceReadyWhenLocked) as? Bool ?? true
    self.tvDelaySeconds = d.double(forKey: Keys.tvDelaySeconds)
    self.lookAtPlayerEnabled = d.bool(forKey: Keys.lookAtPlayer)
    self.tvDelayLine = BroadcastDelay(seconds: d.double(forKey: Keys.tvDelaySeconds))
    self.composer = HUDComposer(config: cfg)
    self.feed = AppModel.makeFeed(demoMode: demo, apiKey: SecretsStore.apiFootballKey)
    self.insights = InsightCoordinator(service: AppModel.makeInsightService())
    self.transcriber = AppModel.makeTranscriber()
    self.voiceAvailable = transcriber != nil
    self.favourites = FavouritesStore.teams
    insights.onChange = { [weak self] state in
      guard let self else { return }
      self.insightState = state
      if !state.isUpdating, let q = state.question, let hud = state.hudContent {
        self.analystLog("answer \(q.label) \"\(hud.title)\" [\(hud.footer)]"
                        + (state.lastError.map { " (fallback: \($0))" } ?? ""))
      }
      self.composer.setInsight(state.hudContent)
      Task { await self.renderIfChanged() }
    }
  }

  /// Wire the mutual reference and kick off scheduling. Called once at launch.
  func attach(glasses: GlassesViewModel) {
    self.glasses = glasses
    glasses.appModel = self
    start()
  }

  // MARK: - Feed selection

  /// Matchsight polls the Premier League, the Champions League, the DFB-Pokal
  /// and Brazil's Série A, Série B and Copa do Brasil.
  static let leagueIds = [ApiFootballFeed.premierLeague, ApiFootballFeed.championsLeague,
                          ApiFootballFeed.germanCup, ApiFootballFeed.brazilSerieA,
                          ApiFootballFeed.brazilSerieB, ApiFootballFeed.brazilCup]

  static func makeFeed(demoMode: Bool, apiKey: String?) -> any MatchFeed {
    if !demoMode, let key = apiKey, !key.isEmpty {
      return ApiFootballFeed(apiKey: key, leagueIds: leagueIds, season: ApiFootballFeed.clubSeason)
    }
    let script = (try? MatchScript.bundled()) ?? MatchScript.empty
    let mock = MockFeed(script: script, speed: 60)
    mock.start()  // begin the match clock immediately so the demo shows as live
    return mock
  }

  /// Meta Model API settings: via the CopaHUD proxy (preferred: the key stays
  /// on the Worker), else directly with a stored Meta key, else nil.
  static func metaConfig() -> MetaModelConfig? {
    if let proxy = SecretsStore.metaProxyURL,
       let base = URL(string: proxy), base.scheme == "https", base.host != nil,
       let token = SecretsStore.metaProxyToken, !token.isEmpty {
      var config = MetaModelConfig()
      config.baseURL = base.appendingPathComponent("v1")
      config.apiKey = nil
      config.headers = ["X-CopaHUD-Token": token]
      return config
    }
    if let key = SecretsStore.metaModelKey, !key.isEmpty {
      var config = MetaModelConfig()
      config.apiKey = key
      return config
    }
    return nil
  }

  /// Muse Spark when Meta access is configured; otherwise the deterministic
  /// mock (footer says "Mock AI", never passed off as live).
  static func makeInsightService() -> any MatchInsightService {
    if let config = metaConfig() { return MetaModelInsightService(config: config) }
    return MockMatchInsightService(delay: .milliseconds(600))
  }

  /// Muse Voice Transcribe needs real Meta access — there is no mock
  /// transcriber (a pretend transcript would be a fabricated capability).
  static func makeTranscriber() -> (any VoiceTranscriber)? {
    metaConfig().map { MetaVoiceTranscriber(config: $0) }
  }

  /// Re-selects the insight backend after the Meta key changes in Settings.
  func refreshInsightService() {
    insights.setService(AppModel.makeInsightService())
    transcriber = AppModel.makeTranscriber()
    voiceAvailable = transcriber != nil
    voiceStatus = nil
    updateVoiceReadiness()
  }

  /// Re-selects the feed after a settings change (API key entered, demo toggled).
  func refreshFeed() {
    let wasDemo = feed is MockFeed
    feed = AppModel.makeFeed(demoMode: demoMode, apiKey: SecretsStore.apiFootballKey)
    dayCache = [:]
    selectDay(selectedDay)
    // Data from the previous feed (e.g. the scripted demo match) must never
    // reach the analyst labelled as the new source — drop it and re-poll.
    lastSnapshot = nil; lastEvents = []; lastLineups = []; lastStats = nil; playerStats = [:]; lastPrediction = nil; predictionFetched = []
    tvDelayLine.clear(); lastPolledStatus = nil; liveClock = LiveMatchClock()
    analystReady = false
    if wasDemo || feed is MockFeed {
      // Into, out of, or restarting the scripted match: the followed fixture
      // belongs to the old feed (or its script restarts at 0-0, which the old
      // engine state would announce as VAR-overturned goals). Start clean and
      // let the next schedule cycle's FollowPolicy pick.
      followedTask?.cancel(); followedTask = nil
      followedFixtureId = nil
      followState = FollowState()
      engine = MatchEngine()
      insights.reset(fixtureId: nil)
      applyToComposer()
    } else {
      insights.reset(fixtureId: followedFixtureId)
      if followedFixtureId != nil { restartFollowedLoop() }
    }
    // Restart the schedule so the new feed is polled without waiting for the
    // current sleep to expire.
    scheduleTask?.cancel()
    scheduleTask = nil
    stopLiveLoops()
    start()
  }

  // MARK: - Settings mutators

  func setTakeoverSeconds(_ value: Double) {
    config.takeoverSeconds = value
    UserDefaults.standard.set(value, forKey: Keys.takeoverSeconds)
    rebuildComposer()
  }

  func setToastsEnabled(_ value: Bool) {
    config.toastsEnabled = value
    UserDefaults.standard.set(value, forKey: Keys.toastsEnabled)
    rebuildComposer()
  }

  func setBatterySaver(_ value: BatterySaver) {
    guard value != config.batterySaver else { return }
    config.batterySaver = value
    UserDefaults.standard.set(value.rawValue, forKey: Keys.batterySaver)
    rebuildComposer()
  }

  /// Reactivate HUD: bring the glasses out of battery saver.
  func wakeHUD() {
    composer.wake()
    Task { await renderNow() }
  }

  func setVoiceReadyWhenLocked(_ value: Bool) {
    voiceReadyWhenLocked = value
    UserDefaults.standard.set(value, forKey: Keys.voiceReadyWhenLocked)
    updateVoiceReadiness()
  }

  func setTVDelay(_ value: Double) {
    tvDelaySeconds = value
    UserDefaults.standard.set(value, forKey: Keys.tvDelaySeconds)
    tvDelayLine.seconds = value
    Task { await deliverDueUpdates() }
  }

  func setLookAtPlayer(_ value: Bool) {
    lookAtPlayerEnabled = value
    UserDefaults.standard.set(value, forKey: Keys.lookAtPlayer)
  }

  /// The live match clock in seconds, once the feed's minute has ticked over
  /// (nil at half-time, in stoppage time, or before the first tick).
  func liveClockSeconds() -> TimeInterval? { liveClock.seconds(at: Date()) }

  /// Sync with TV: the fan tapped as the TV clock reached `tvMinute`:00.
  /// Sets the TV delay on success; nil when there is no live clock yet.
  func syncTV(tvMinute: Int) -> TVSync.Outcome? {
    guard let live = liveClockSeconds() else { return nil }
    let outcome = TVSync.delay(liveSeconds: live, tvMinute: tvMinute)
    glasses?.dbg("tv sync: live \(Int(live) / 60):\(String(format: "%02d", Int(live) % 60)), TV \(tvMinute):00 → \(outcome)")
    if case let .delay(seconds) = outcome { setTVDelay(seconds) }
    return outcome
  }

  func setDemoMode(_ value: Bool) {
    demoMode = value
    UserDefaults.standard.set(value, forKey: Keys.demoMode)
    refreshFeed()
  }

  /// HUDConfig has no public setter on the composer, so a config change
  /// reseeds the composer with the latest deck data (resetting the deck page).
  private func rebuildComposer() {
    composer = HUDComposer(config: config)
    applyToComposer()
    Task { await renderNow() }
  }

  // MARK: - Following

  /// Manual follow (a tap on Today): wins over auto-follow until it ends.
  func follow(fixtureId: Int) {
    follow(fixtureId: fixtureId, manual: true)
  }

  private func follow(fixtureId: Int, manual: Bool) {
    followState = FollowState(fixtureId: fixtureId, isManual: manual,
                              suppressed: followState.suppressed)
    if let old = followedFixtureId, old != fixtureId { engine.reset(fixtureId: old) }
    followedFixtureId = fixtureId
    lineupsFetched.remove(fixtureId)
    halfTimeLineupRefreshed = false
    lastSnapshot = nil; lastEvents = []; lastLineups = []; lastStats = nil; playerStats = [:]; lastPrediction = nil; predictionFetched = []
    tvDelayLine.clear(); lastPolledStatus = nil; liveClock = LiveMatchClock()
    lastFollowedPollOk = nil
    analystReady = false
    insights.reset(fixtureId: fixtureId)
    restartFollowedLoop()
    ensureTickLoop()
  }

  func unfollow() {
    // Auto-follow must not bring back the match the fan just dismissed.
    if let id = followedFixtureId { followState.suppressed.insert(id) }
    followState.fixtureId = nil
    followState.isManual = false
    followState.finishedAt = nil
    if let id = followedFixtureId { engine.reset(fixtureId: id) }
    followedFixtureId = nil
    followedTask?.cancel(); followedTask = nil
    lastSnapshot = nil; lastEvents = []; lastLineups = []; lastStats = nil; playerStats = [:]; lastPrediction = nil; predictionFetched = []
    tvDelayLine.clear(); lastPolledStatus = nil; liveClock = LiveMatchClock()
    analystReady = false
    insights.reset(fixtureId: nil)
  }

  // MARK: - AI analyst

  /// Phone "Ask the analyst": jump the glasses to the insight page and ask.
  /// The answer (or the data-only fallback) arrives via `insights.onChange`.
  func askAnalyst(_ question: InsightQuestion) {
    guard let context = insightContext() else {
      // Never a silent no-op: the tap must say why nothing happened.
      analystLog("ask \(question.label) ignored: no match data (followed \(followedFixtureId.map(String.init) ?? "none"))")
      voiceStatus = followedFixtureId == nil ? "No match followed yet" : "Waiting for match data…"
      return
    }
    let events = context.facts.filter { $0.text.contains("'") }.count
    analystLog("ask \(question.label): \(context.facts.count) facts, \(events) events, \(context.headline)")
    composer.showInsightPage()
    insights.ask(question, context: context)
    Task { await renderNow() }
  }

  /// Ask by voice: Muse Voice Transcribe (biased toward this match's names)
  /// turns the recording into text, then Muse Spark answers it like a preset.
  func askByVoice(wav: Data) {
    guard let transcriber else {
      voiceLog("no transcriber"); voiceStatus = "Voice needs Meta AI (Settings)"
      flashListening("🎙 Voice needs Meta AI (Settings)"); return
    }
    guard analystReady else {
      voiceLog("no match data yet"); voiceStatus = "Waiting for match data…"
      flashListening("🎙 Waiting for match data…"); return
    }
    voiceStatus = "Transcribing…"
    // The glasses show each step: Transcribing… → the question with
    // "Thinking…" on the insight page → the answer.
    setListening("🎙 Transcribing…")
    composer.showInsightPage()
    Task { await renderNow() }
    let keywords = voiceKeywords()
    Task { [weak self] in
      do {
        let text = try await transcriber.transcribe(wav: wav, keywords: keywords)
        guard let self else { return }
        guard !text.isEmpty else {
          self.voiceLog("empty transcript"); self.voiceStatus = "Didn't catch that"
          self.flashListening("🎙 Didn't catch that. Hold and ask again", seconds: 3)
          return
        }
        self.voiceLog("heard \"\(text)\"")
        self.voiceStatus = "Heard: \u{201C}\(text)\u{201D}"
        if ShirtNumberLookup.isLookRequest(text) {
          guard self.lookAtPlayerEnabled else {
            self.voiceLog("look: phrase heard, but Look at a player is off")
            self.voiceStatus = "Turn on Settings → Look at a player"
            self.flashListening("📷 Turn on Look at a player in Settings", seconds: 3)
            return
          }
          self.voiceLog("look: phrase heard")
          await self.lookAtPlayer()
          return
        }
        self.setListening(nil)
        self.askAnalyst(.spoken(text))
      } catch {
        guard let self else { return }
        self.voiceLog("transcribe failed: \(error)")
        self.voiceStatus = "Couldn't transcribe (\(AppModel.describe(error)))"
        self.flashListening("🎙 Couldn't hear the question (\(AppModel.describe(error)))", seconds: 3)
      }
    }
  }

  /// "Who's this?": one glasses photo, the shirt number read on the phone,
  /// and that starter's detail card. Only ever names someone in the starting
  /// XIs; every failure says so on the glasses.
  private func lookAtPlayer() async {
    guard !lastLineups.isEmpty else {
      voiceLog("look: no lineups"); flashListening("📷 No lineups for this match yet", seconds: 3); return
    }
    guard let glasses else { return }
    setListening("📷 Hold still…")
    await renderNow()
    let data: Data
    switch await glasses.takePhoto() {
    case .success(let photo): data = photo
    case .failure(let why):
      voiceLog("look: \(why)"); voiceStatus = "Camera: \(why)"
      flashListening("📷 Camera: \(why)", seconds: 3)
      return
    }
    setListening("📷 Reading the shirt number…")
    await renderNow()
    let candidates = await ShirtNumberReader.candidates(in: data)
    let result = ShirtNumberLookup.find(candidates, in: lastLineups)
    voiceLog("look: \(candidates.count) text pieces → \(result)")
    switch result {
    case let .player(name, teamId, index):
      voiceStatus = "That's \(name)"
      setListening(nil)
      composer.showPlayer(teamId: teamId, index: index, now: Date())
      await renderNow()
    case let .ambiguous(number, names):
      voiceStatus = "#\(number): \(names.joined(separator: " or "))"
      flashListening("📷 #\(number): \(names.joined(separator: " or "))", seconds: 4)
    case let .notInLineup(number):
      voiceStatus = "No #\(number) in either starting XI"
      flashListening("📷 No #\(number) in either starting XI", seconds: 3)
    case .noNumber:
      voiceStatus = "Couldn't read a shirt number"
      flashListening("📷 Couldn't read a shirt number", seconds: 3)
    }
  }

  /// Team names, every lineup name, and each surname — the words the
  /// transcriber is most likely to mishear.
  private func voiceKeywords() -> [String] {
    var words: [String] = []
    if let s = lastSnapshot { words += [s.home.name, s.away.name] }
    for player in lastLineups.flatMap(\.startXI) {
      words.append(player.name)
      if let surname = player.name.split(separator: " ").last { words.append(String(surname)) }
    }
    return words
  }

  static func describe(_ error: Error) -> String {
    switch error as? InsightError {
    case .unauthorized: return "key rejected"
    case .rateLimited: return "rate limited"
    case .timeout: return "timed out"
    case let .http(code, _): return "HTTP \(code)"
    case .network: return "offline"
    case .malformedResponse: return "bad response"
    case .invalid: return "failed grounding check"
    case nil: return "error"
    }
  }

  /// Grounded facts for the followed match, or nil before the first poll.
  private func insightContext() -> MatchInsightContext? {
    guard let snapshot = lastSnapshot, snapshot.fixtureId == followedFixtureId else { return nil }
    return MatchInsightContext.build(snapshot: snapshot, events: lastEvents,
                                     lineups: lastLineups, stats: lastStats,
                                     isScripted: feed is MockFeed)
  }

  // MARK: - Band / phone controls

  /// A Neural Band gesture read through DAT 1.0 Inputs.
  func hudInput(_ input: HUDInput) {
    composer.handle(input, now: Date())
    Task { await renderNow() }
  }

  /// Pinch-and-hold began on the glasses: start listening and say so on the HUD.
  func voiceHoldBegan() {
    guard voiceAvailable else { voiceLog("not configured"); flashListening("🎙 Voice needs Meta AI (Settings)"); return }
    guard analystReady else { voiceLog("no match data yet"); flashListening("🎙 Waiting for match data…"); return }
    setListening("🎙 Listening… release to ask")
    // The release awaits this start (permission prompt + engine), so letting
    // go early can't leave the mic running — same rule as the phone button.
    voiceStart = Task { [weak self] in
      guard let self else { return }
      await self.renderNow()
      await self.recorder.start()
      if let error = self.recorder.lastError {
        self.voiceLog("recorder: \(error)")
        self.flashListening("🎙 \(error)")
      } else {
        self.voiceLog("recording")
      }
    }
  }

  /// Released: stop, transcribe and ask (the answer lands on the insight page).
  func voiceHoldEnded() async {
    guard let wav = await finishVoiceCapture() else {
      voiceLog("nothing captured")
      if recorder.lastError == nil { flashListening("🎙 Didn't hear anything. Hold and ask again", seconds: 3) }
      return
    }
    voiceLog("captured \(wav.count) bytes")
    askByVoice(wav: wav)
  }

  /// The glasses session ended mid-hold: stop the mic and drop the recording.
  func voiceHoldCancelled() async {
    _ = await finishVoiceCapture()
    voiceLog("hold cancelled")
  }

  private func finishVoiceCapture() async -> Data? {
    let start = voiceStart
    voiceStart = nil
    await start?.value
    let wav = await recorder.stop()
    // Leave a recorder error on screen; flashListening clears it.
    if recorder.lastError == nil {
      setListening(nil)
      await renderNow()
    }
    return wav
  }

  // MARK: - Mic readiness (ask from the glasses with the phone locked)

  /// Glasses connected (or user disconnected) — the mic follows.
  @ObservationIgnored private var glassesConnected = false

  /// The glasses session started. Gets the mic ready while the app can still
  /// open it; a reconnect after a drop finds it already running.
  func glassesSessionStarted() {
    glassesConnected = true
    updateVoiceReadiness()
  }

  /// The user disconnected the glasses. A device-side drop does NOT call
  /// this: the mic stays ready so the auto-reconnect works with the phone
  /// locked (the running audio session also keeps the app awake).
  func glassesDisconnectedByUser() {
    glassesConnected = false
    updateVoiceReadiness()
  }

  private func updateVoiceReadiness() {
    guard voiceReadyWhenLocked, glassesConnected, voiceAvailable else {
      if recorder.isArmed { voiceLog("mic ready off") }
      recorder.disarm()
      return
    }
    guard !recorder.isArmed else { return }
    Task { [weak self] in
      guard let self else { return }
      if await self.recorder.arm() {
        self.voiceLog("mic ready (phone can be locked)")
      } else {
        self.voiceLog("mic ready failed: \(self.recorder.lastError ?? "unknown")")
      }
    }
  }

  private func voiceLog(_ s: String) { glasses?.dbg("voice: \(s)") }
  private func analystLog(_ s: String) { glasses?.dbg("analyst: \(s)") }

  /// Every banner change bumps the token, so a flash's delayed clear can't
  /// wipe a banner set after it.
  private func setListening(_ text: String?) {
    listeningToken += 1
    composer.setListening(text)
  }

  /// Shows a short push-to-talk message on the glasses (2 s by default).
  private func flashListening(_ text: String, seconds: Int = 2) {
    setListening(text)
    let token = listeningToken
    Task { [weak self] in
      await self?.renderNow()
      try? await Task.sleep(for: .seconds(seconds))
      guard let self, self.listeningToken == token else { return }
      self.setListening(nil)
      await self.renderNow()
    }
  }

  /// Resolved tap burst from the glasses card (count already resolved by the
  /// 350ms window in GlassesViewModel).
  func tapBurst(count: Int) {
    composer.handleTapBurst(count: count, now: Date())
    Task { await renderNow() }
  }

  /// Phone-side swipe-right: step the STARTING XI carousel one player back.
  func carouselBack() {
    composer.handleCarouselBack()
    Task { await renderNow() }
  }

  /// True while a goal/red-card takeover is the active frame body.
  var hasTakeover: Bool { composer.hasTakeover }

  /// Phone-side dismiss: clears the active takeover and drains the queue.
  func clearTakeovers() {
    composer.clearAllTakeovers()
    Task { await renderNow() }
  }

  /// The XI the glasses carousel is currently backed by, for the phone tiles.
  var currentXI: [LineupPlayer]? { composer.currentXI }

  /// Which portrait tile is active on the glasses right now.
  var currentPlayerIndex: Int { composer.hudPlayerIndex }

  /// The club behind the current lineup page (crest on the formation board).
  var currentXITeam: Team? { composer.currentXITeam }

  /// The followed match in one line, for the compact scoreboard on deck pages.
  var scoreSummary: ScoreSummary? {
    guard let s = lastSnapshot else { return nil }
    let h = TeamStyle.style(for: s.home), a = TeamStyle.style(for: s.away)
    return ScoreSummary(homeCode: h.code, awayCode: a.code, score: s.score,
                        homeCrestURL: h.crestURL, awayCrestURL: a.crestURL)
  }

  /// Team name for the lineup carousel header (home/away per the HUD page).
  var currentXITeamName: String? { composer.currentXITeamName }

  /// Phone-side tap on a player tile — jumps the glasses to that card.
  func goToPlayer(index: Int) {
    composer.goToPlayer(index)
    Task { await renderNow() }
  }

  /// LiveView's alert-pause toggle = the 3-pinch "cinema mode" vocabulary.
  func toggleAlertsPaused() {
    composer.handleTapBurst(count: 3, now: Date())
    Task { await renderNow() }
  }

  /// Called by GlassesViewModel when the display (re)connects — push current state.
  func handleGlassesReady() async {
    await renderNow()
  }

  // MARK: - Scheduling
  //
  // Zero polling outside match windows: the schedule loop only spins up the live
  // loops when something is live or a kickoff is imminent, and sleeps until the
  // next `PollPlanner.nextPollWindow` otherwise.

  func start() {
    guard scheduleTask == nil else { return }
    scheduleTask = Task { [weak self] in await self?.scheduleRun() }
  }

  func stop() {
    scheduleTask?.cancel(); scheduleTask = nil
    stopLiveLoops()
    followedTask?.cancel(); followedTask = nil
  }

  private func scheduleRun() async {
    while !Task.isCancelled {
      await refreshFixtures()
      applyFollowPolicy()
      let now = Date()
      let nextWindow = PollPlanner.nextPollWindow(fixtures: fixtures, now: now)
      let anyLive = fixtures.contains { $0.status.isLive }
      let kickoffImminent = nextWindow.map { $0.timeIntervalSince(now) < 120 } ?? false

      if anyLive || kickoffImminent || lastSnapshot?.status.isLive == true {
        ensureLiveLoops()
      } else {
        stopLiveLoops()
      }

      var sleep: TimeInterval
      if anyLive {
        sleep = 60   // re-check the fixture list periodically while matches run
      } else if let next = nextWindow {
        sleep = max(15, min(next.timeIntervalSince(now), 1800))
      } else {
        sleep = 1800
      }
      // A favourite's match is today but not live yet: wake often enough not
      // to miss the pre-kickoff follow window.
      let favouritePending = fixtures.contains {
        $0.status == .notStarted && involvesFollowFavourite($0)
      }
      if favouritePending { sleep = min(sleep, FollowPolicy.preKickoffWindow / 2) }
      try? await Task.sleep(for: .seconds(sleep))
    }
  }

  private func ensureLiveLoops() {
    if followedFixtureId != nil, followedTask == nil { restartFollowedLoop() }
    if othersTask == nil { othersTask = Task { [weak self] in await self?.runOthersLoop() } }
    ensureTickLoop()
  }

  private func ensureTickLoop() {
    if tickTask == nil { tickTask = Task { [weak self] in await self?.runTickLoop() } }
  }

  private func stopLiveLoops() {
    othersTask?.cancel(); othersTask = nil
    tickTask?.cancel(); tickTask = nil
  }

  private func restartFollowedLoop() {
    followedTask?.cancel()
    followedTask = Task { [weak self] in await self?.runFollowedLoop() }
  }

  // MARK: - Favourites + auto-follow

  /// Saves the picks and re-runs auto-follow straight away.
  func setFavourites(_ teams: [Team]) {
    favourites = teams
    FavouritesStore.teams = teams
    applyFollowPolicy()
  }

  /// A league's clubs for the team picker: cached per league, fetched with
  /// the API-Football key (even in demo mode); empty without a key.
  func clubs(leagueId: Int) async -> [Team] {
    if let cached = FavouritesStore.cachedClubs(leagueId: leagueId), !cached.isEmpty { return cached }
    guard let key = SecretsStore.apiFootballKey, !key.isEmpty else { return [] }
    let catalogue = ApiFootballFeed(apiKey: key, leagueIds: AppModel.leagueIds,
                                    season: ApiFootballFeed.clubSeason)
    guard let clubs = try? await catalogue.clubs(leagueId: leagueId), !clubs.isEmpty else { return [] }
    FavouritesStore.cacheClubs(clubs, leagueId: leagueId)
    return clubs
  }

  /// The scripted demo match is playing (MockFeed), not live data.
  var isScripted: Bool { feed is MockFeed }

  /// Teams auto-follow looks for. Demo mode follows the scripted main match
  /// only — every scripted team would let the side match win the tie-break.
  private var followFavourites: Set<Int> {
    if let mock = feed as? MockFeed { return mock.primaryTeamIds }
    return Set(favourites.map(\.id))
  }

  /// Teams whose other-match goals may toast. Demo mode: every scripted team.
  private var toastFavourites: Set<Int> {
    if feed is MockFeed { return Set(fixtures.flatMap { [$0.home.id, $0.away.id] }) }
    return Set(favourites.map(\.id))
  }

  private func involvesFollowFavourite(_ f: Fixture) -> Bool {
    let ids = followFavourites
    return ids.contains(f.home.id) || ids.contains(f.away.id)
  }

  /// Runs FollowPolicy against today's fixtures and follows its pick.
  private func applyFollowPolicy() {
    if let snap = lastSnapshot {
      followState.noteFollowedStatus(snap.status, fixtureId: snap.fixtureId, now: Date())
    }
    let decision = FollowPolicy.decide(fixtures: fixtures, favourites: followFavourites,
                                       state: followState, now: Date())
    if case let .follow(id) = decision, id != followedFixtureId {
      glasses?.dbg("follow: auto → \(id)")
      follow(fixtureId: id, manual: false)
    }
    // Reliability run: one line per decision, counted by `reliability-report`.
    let findings = FollowAudit.check(fixtures: fixtures, favourites: followFavourites,
                                     state: followState, shownFixtureId: lastSnapshot?.fixtureId,
                                     now: Date())
    glasses?.dbg(FollowAudit.logLine(findings, followed: followedFixtureId))
  }

  // MARK: - Day strip

  var isShowingToday: Bool { DayStrip.isToday(selectedDay, now: Date()) }

  /// Show another day's fixtures on the Today tab. Today keeps its live list;
  /// following and the glasses only ever use today's matches.
  func selectDay(_ day: Date, forceReload: Bool = false) {
    selectedDay = day
    dayTask?.cancel()
    guard !isShowingToday else { dayFixtures = []; isLoadingDay = false; return }
    if !forceReload, let cached = dayCache[day], Date().timeIntervalSince(cached.at) < 600 {
      dayFixtures = cached.fixtures; isLoadingDay = false; return
    }
    dayFixtures = []
    isLoadingDay = true
    dayTask = Task { [weak self] in
      guard let self else { return }
      let feed = self.feed
      do {
        let list = try await feed.fixtures(on: day)
        guard !Task.isCancelled, self.selectedDay == day else { return }
        self.dayCache[day] = (list, Date())
        self.dayFixtures = list
      } catch let e as FeedError {
        guard !Task.isCancelled else { return }
        self.banner = e
      } catch {
        // Transient network: the empty list says so; pull to refresh retries.
      }
      if self.selectedDay == day { self.isLoadingDay = false }
    }
  }

  /// Pull to refresh: today's live list, or the selected day's.
  func refreshSelectedDay() async {
    if isShowingToday { await refreshFixtures(); return }
    selectDay(selectedDay, forceReload: true)
    await dayTask?.value
  }

  // MARK: - Poll loops

  func refreshFixtures() async {
    do { fixtures = try await feed.todaysFixtures(); clearBannerIfRecovered() }
    catch let e as FeedError { banner = e }
    catch { /* transient network — leave fixtures as-is */ }
    if let live = try? await feed.otherLive() {
      liveNow = live.sorted { ($0.elapsedMinutes ?? 0) > ($1.elapsedMinutes ?? 0) }
    }
    // The feed fetches the same favourites at most every 6 h.
    if let next = try? await feed.upcomingFixtures(teamIds: favourites.map(\.id)) {
      upcoming = ComingUp.list(next, now: Date())
    }
  }

  private func runFollowedLoop() async {
    while !Task.isCancelled {
      guard let id = followedFixtureId else { break }
      do {
        let snap = try await feed.liveSnapshot(fixtureId: id)
        let events = try await feed.events(fixtureId: id)

        // Lineups: once per fixture, refetched at half-time (subs/formation
        // shifts). The API answers 200 with an empty array until lineups are
        // announced (~20-40 min before kickoff), so only a non-empty response
        // counts as fetched — otherwise keep retrying each poll.
        let needLineups = !lineupsFetched.contains(id)
          || (snap.status == .halfTime && !halfTimeLineupRefreshed)
        if needLineups {
          if let lineups = try? await feed.lineups(fixtureId: id), !lineups.isEmpty {
            lastLineups = lineups
            lineupsFetched.insert(id)
            if snap.status == .halfTime { halfTimeLineupRefreshed = true }
          }
        }

        // Stats for the stats deck page — served from the feed's 60s cache,
        // so this costs no extra API requests. Best-effort.
        let freshStats = try? await feed.stats(fixtureId: id)
        // Player-card stats once the ball is rolling — the feed caches them
        // for 60 s, so at most one request a minute. Best-effort.
        let ballRolled = snap.elapsedMinutes != nil
        let freshPlayerStats = ballRolled ? (try? await feed.playerStats(fixtureId: id)) : nil
        // The pre-match prediction, once per fixture (best-effort).
        var freshPrediction: WinProbability?
        if !predictionFetched.contains(id) {
          predictionFetched.insert(id)
          freshPrediction = try? await feed.prediction(fixtureId: id)
        }

        // follow()/unfollow() cancel this loop, but `try?` awaits above
        // swallow cancellation — never publish an old match's data (or ask
        // the analyst about it) after the user switched.
        guard !Task.isCancelled, followedFixtureId == id else { break }

        if let freshPrediction { lastPrediction = freshPrediction }
        lastPolledStatus = snap.status
        liveClock.observe(minute: snap.elapsedMinutes, status: snap.status, at: Date())
        lastFollowedPollOk = Date()
        isStale = false
        clearBannerIfRecovered()
        glasses?.dbg("poll \(id): \(snap.status.rawValue) \(snap.elapsedMinutes.map { "\($0)'" } ?? "–") \(snap.score.home)-\(snap.score.away), \(events.count) events"
                     + (tvDelaySeconds > 0 ? " (shown after \(Int(tvDelaySeconds)) s TV delay)" : ""))
        // Score, events and stats wait out the TV delay (none by default).
        tvDelayLine.push(FollowedUpdate(fixtureId: id, snapshot: snap, events: events,
                                        stats: freshStats, playerStats: freshPlayerStats), at: Date())
        await deliverDueUpdates()
      } catch let e as FeedError {
        banner = e   // glasses stay on last frame; phone shows the banner
      } catch {
        // transient network: silent retry; staleness surfaces via the tick loop
      }

      let status = lastPolledStatus ?? .notStarted
      // followedInterval is nil pre-kickoff/finished; poll at 60s until kickoff,
      // and stop entirely once the match is over (finished, abandoned, postponed…).
      let interval = PollPlanner.followedInterval(status: status)
        ?? (status.isOver ? nil : 60)
      guard let interval else { break }
      try? await Task.sleep(for: .seconds(interval))
    }
  }

  /// Shows the followed-match polls whose TV delay is over, oldest first.
  /// Called after each poll and by the 1 Hz tick.
  private func deliverDueUpdates() async {
    let due = tvDelayLine.due(now: Date())
    guard !due.isEmpty else { return }
    for update in due where update.fixtureId == followedFixtureId {
      let moments = engine.ingestFollowed(snapshot: update.snapshot, events: update.events)
      record(moments)
      lastSnapshot = update.snapshot
      analystReady = true
      lastEvents = update.events
      lastStats = update.stats ?? lastStats
      if let fresh = update.playerStats, !fresh.isEmpty { playerStats = fresh }
      applyToComposer()
      // Crest intro on the first poll of a newly followed match (the
      // composer never repeats it for the same fixture).
      composer.showMatchIntro(now: Date())
      composer.enqueue(moments, now: Date())
    }
    if let context = insightContext() { insights.contextChanged(context) }
    await renderNow()
  }

  private func runOthersLoop() async {
    while !Task.isCancelled {
      do {
        let allLive = try await feed.otherLive()
        liveNow = allLive.sorted { ($0.elapsedMinutes ?? 0) > ($1.elapsedMinutes ?? 0) }
        let toastTeams = toastFavourites
        let others = allLive.filter {
          $0.fixtureId != followedFixtureId
            && (toastTeams.contains($0.home.id) || toastTeams.contains($0.away.id))
        }
        lastOthers = others

        let raw = engine.ingestOthers(others)
        // Best-effort ONE-SHOT scorer enrichment for cross-match goals. On
        // failure the toast simply omits the scorer — never retried.
        var moments: [MatchMoment] = []
        for moment in raw {
          if case .otherMatchGoal(let snapshot, _) = moment.kind {
            let scorer = try? await latestScorer(fixtureId: snapshot.fixtureId)
            moments.append(MatchMoment(
              fixtureId: moment.fixtureId,
              kind: .otherMatchGoal(snapshot: snapshot, scorer: scorer),
              score: moment.score, minute: moment.minute))
          } else {
            moments.append(moment)
          }
        }
        record(moments)
        clearBannerIfRecovered()

        applyToComposer()
        composer.enqueue(moments, now: Date())
        await renderNow()
      } catch let e as FeedError {
        banner = e
      } catch {
        // transient — retry next cycle
      }

      let interval = PollPlanner.othersInterval(anyLive: true) ?? 60
      try? await Task.sleep(for: .seconds(interval))
    }
  }

  /// 1 Hz: advance composer time-driven state, re-render only when the frame
  /// changed (HUDFrame is Equatable), and flip the staleness marker.
  private func runTickLoop() async {
    while !Task.isCancelled {
      let now = Date()
      updateStaleness(now: now)
      await deliverDueUpdates()
      composer.tick(now: now)
      let f = composer.frame(now: now)
      if f != frame {
        frame = f
        await glasses?.render(f)
      }
      try? await Task.sleep(for: .seconds(1))
    }
  }

  // MARK: - Helpers

  private func latestScorer(fixtureId: Int) async throws -> String? {
    let events = try await feed.events(fixtureId: fixtureId)
    return events.last(where: { event in
      if case .goal = event.kind { return true }
      return false
    })?.player
  }

  private func applyToComposer(now: Date = Date()) {
    // League name only ("Premier League", not "Premier League · England"):
    // the pill's label row is short.
    composer.setCompetition(fixtures.first { $0.id == followedFixtureId }?
      .competition?.components(separatedBy: " · ").first)
    composer.setPrediction(lastPrediction)
    composer.update(followed: lastSnapshot, events: lastEvents, lineups: lastLineups,
                    others: lastOthers, stats: lastStats, isStale: isStale, now: now)
    composer.setInsight(insightState.hudContent)   // survives rebuildComposer()
  }

  /// Like the 1 Hz tick: only sends when the frame actually changed, so insight
  /// state changes off the insight page cost no display.send.
  private func renderIfChanged() async {
    let now = Date()
    composer.tick(now: now)
    let f = composer.frame(now: now)
    guard f != frame else { return }
    frame = f
    await glasses?.render(f)
  }

  private func renderNow() async {
    let now = Date()
    composer.tick(now: now)
    let f = composer.frame(now: now)
    frame = f
    await glasses?.render(f)
  }

  private func record(_ moments: [MatchMoment]) {
    guard !moments.isEmpty else { return }
    lastMoments.append(contentsOf: moments)
    if lastMoments.count > 30 { lastMoments.removeFirst(lastMoments.count - 30) }
  }

  /// >60s since the last successful followed poll → stale (spec Error handling).
  private func updateStaleness(now: Date) {
    guard let last = lastFollowedPollOk else { return }
    let stale = now.timeIntervalSince(last) > 60
    if stale != isStale {
      isStale = stale
      applyToComposer(now: now)
    }
  }

  private func clearBannerIfRecovered() {
    if banner != nil { banner = nil }
  }

  func dismissBanner() { banner = nil }

  private enum Keys {
    static let takeoverSeconds = "takeoverSeconds"
    static let toastsEnabled = "toastsEnabled"
    static let demoMode = "demoMode"
    static let voiceReadyWhenLocked = "voiceReadyWhenLocked"
    static let tvDelaySeconds = "tvDelaySeconds"
    static let lookAtPlayer = "lookAtPlayer"
    static let batterySaver = "batterySaver"
  }
}

