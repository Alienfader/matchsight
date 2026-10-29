import Foundation
import MWDATCamera
import MWDATCore
import MWDATDisplay
import MWDATInputs
import Observation
import SwiftUI
import CopaHUDCore

/// Owns the Meta DAT session/display lifecycle for CopaHUD. The
/// session/registration/display plumbing, retry ladder, scenePhase recovery and
/// `dbg()` debug log come from an earlier glasses prototype and were
/// field-tested on hardware.
///
/// The HUD is driven by a
/// single render path (`render(_:)`) fed by `AppModel`, and the Neural Band
/// vocabulary is the 350ms tap-burst resolver that forwards to
/// `AppModel.tapBurst(count:)`.
@Observable
@MainActor
final class GlassesViewModel {
  /// DAT connection lifecycle phase. Carried over from the mirror app so the
  /// PairingView/LiveView bindings keep working unchanged.
  enum ConnPhase: Equatable {
    case unregistered, pairing, ready, error(String)
  }

  /// Set by `AppModel` after construction (mutual reference): tap bursts resolve
  /// to `appModel.tapBurst`, and on display reconnect we ask the conductor to
  /// re-render the current frame.
  weak var appModel: AppModel?

  // MARK: DAT lifecycle state (verbatim from AgentViewModel)
  private(set) var connPhase: ConnPhase = .unregistered
  var registrationState: RegistrationState
  var lastStatus: String = ""
  var showError = false
  var errorMessage = ""
  var requiresDATAppUpdate = false
  private(set) var debugLog: [String] = []   // last 120 entries, newest last

  private let wearables: WearablesInterface

  @ObservationIgnored private var deviceSelector: AutoDeviceSelector
  @ObservationIgnored private var session: DeviceSession?
  @ObservationIgnored private var display: Display?
  /// DAT 1.0 Inputs: raw Neural Band gestures. While active, the glasses'
  /// own focus/tap handling no longer sees them, so CopaHUD maps them itself:
  /// pinch / swipe right = next, swipe left = previous, swipe up = home,
  /// pinch-and-hold (≥ holdThreshold) = push-to-talk to the AI analyst.
  @ObservationIgnored private var inputs: Inputs?
  @ObservationIgnored private var inputsTask: Task<Void, Never>?
  @ObservationIgnored private var inputsStateToken: AnyListenerToken?
  @ObservationIgnored private var inputsErrorToken: AnyListenerToken?
  /// Re-arming Inputs after the glasses turned them off mid-session.
  @ObservationIgnored private var inputsRearmTask: Task<Void, Never>?
  @ObservationIgnored private var inputsRearmAttempts = 0
  @ObservationIgnored private var inputsRearmsThisSession = 0
  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var sessionStateTask: Task<Void, Never>?
  @ObservationIgnored private var sessionErrorTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateToken: AnyListenerToken?
  // "Hey Meta, start Matchsight" (DAT 1.0 voice invocations, experimental).
  @ObservationIgnored private var voiceLaunchStream: VoiceInvocationsStream?
  @ObservationIgnored private var voiceLaunchTokens: [AnyListenerToken] = []
  @ObservationIgnored private var voiceLaunchTask: Task<Void, Never>?
  @ObservationIgnored private var isDisconnecting = false

  /// The frame currently shown on the glasses; nil when no HUD is active.
  /// Doubles as the phase-guard for tap handling (DAT rule #3) and the source
  /// for re-render on display reconnect (spec Error handling section).
  @ObservationIgnored private var currentFrame: HUDFrame?
  @ObservationIgnored private let remoteImages = RemoteImageCache()
  @ObservationIgnored private var isSending = false
  @ObservationIgnored private var renderPending = false
  /// Battery saver turned the display off; the next awake frame turns it on.
  @ObservationIgnored private var displayAsleep = false
  /// When battery saver asked the display to come back, until it has.
  @ObservationIgnored private var wakeStartedAt: Date?
  /// Why the glasses ended the session, kept for the status line.
  @ObservationIgnored private var sessionEndReason: String?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.registrationState = wearables.registrationState
    self.deviceSelector = AutoDeviceSelector(wearables: wearables, filter: { $0.supportsDisplay() })
    self.connPhase = wearables.registrationState == .registered ? .pairing : .unregistered

    registrationTask = Task { [weak self] in
      guard let self else { return }
      for await state in self.wearables.registrationStateStream() {
        self.registrationState = state
        if state == .registered {
          self.startVoiceLaunch()
          if case .unregistered = self.connPhase { self.connPhase = .pairing }
          await self.startSessionIfNeeded()
        } else if state == .unavailable || state == .available {
          await self.teardown(); self.connPhase = .unregistered
        }
      }
    }
  }

  // MARK: - Debug log (earned its keep)

  func dbg(_ s: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    debugLog.append("[\(ts)] \(s)")
    print("[CopaHUD] \(s)")   // mirrored to the device console (devicectl --console)
    if debugLog.count > 120 { debugLog.removeFirst(debugLog.count - 120) }
    #if DEBUG
    Self.appendToLogFile("\(Date().ISO8601Format()) \(s)\n")
    #endif
  }

  #if DEBUG
  /// Debug builds keep the log in Documents/debug.log, so a session started
  /// from the phone (no console attached) can be read afterwards. Over 2 MB,
  /// it starts again from the newer half.
  private static let logFile = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("debug.log")

  private static func appendToLogFile(_ line: String) {
    guard let data = line.data(using: .utf8) else { return }
    guard let handle = try? FileHandle(forWritingTo: logFile) else {
      try? data.write(to: logFile); return
    }
    defer { try? handle.close() }
    if let size = try? handle.seekToEnd(), size > 2_000_000,
       let old = try? Data(contentsOf: logFile) {
      try? old.suffix(1_000_000).write(to: logFile)
      return appendToLogFile(line)
    }
    try? handle.write(contentsOf: data)
  }
  #endif

  // MARK: - Render path (single source of HUD truth)
  //
  // The ONLY way a layout reaches the glasses. `supersed` errors under rapid
  // sends are normal — swallowed (DAT rule #7). The card binds exactly one tap
  // target (DAT rule #1), wired to the tap-burst resolver.

  func render(_ frame: HUDFrame) async {
    currentFrame = frame
    guard display != nil else { dbg("render: no display"); return }
    // One send at a time: frames that arrive meanwhile collapse into the
    // latest, sent when the current one finishes. Phone-drawn pages are
    // pictures, and a burst of them (connect, crests landing) timed out.
    if isSending { renderPending = true; return }
    isSending = true
    defer { isSending = false }
    repeat {
      renderPending = false
      guard let display, let latest = currentFrame else { break }
      if latest.displayOff { sleepDisplay(display); continue }
      // Waking: the display's .started listener sends the current frame.
      if displayAsleep { wakeDisplay(display); break }
      if wakeStartedAt != nil { break }
      await send(latest, to: display)
    } while renderPending
  }

  // MARK: - Battery saver (display off when idle)

  private func sleepDisplay(_ display: Display) {
    guard !displayAsleep else { return }
    displayAsleep = true
    wakeStartedAt = nil
    dbg("battery saver: display off")
    display.stop()
  }

  private func wakeDisplay(_ display: Display) {
    displayAsleep = false
    wakeStartedAt = Date()
    dbg("battery saver: display on")
    display.start()
    // One retry if the display hasn't come back; then say so on the phone.
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard let self, self.wakeStartedAt != nil, let display = self.display else { return }
      self.dbg("battery saver: display didn't wake in 5 s, retrying")
      display.start()
      try? await Task.sleep(for: .seconds(5))
      guard self.wakeStartedAt != nil else { return }
      self.wakeStartedAt = nil
      self.dbg("battery saver: display still off")
      self.lastStatus = "Display didn't wake — tap Reactivate HUD"
    }
  }

  /// "card Saka detail", "insight", … for the debug log: what the glasses got.
  private static func pageName(_ frame: HUDFrame) -> String {
    switch frame.body {
    case .panel: return "panel"
    case .insight: return "insight"
    case .events: return "events"
    case .lineup: return "XI board"
    case let .playerCard(c): return "card \(c.lastName)\(c.isDetail ? " detail" : "")"
    case .stats: return "stats"
    case .otherLive: return "other live"
    case .takeover: return "takeover"
    case .intro: return "intro"
    case .message: return "message"
    case .quiet: return "quiet"
    case .guide: return "guide"
    }
  }

  private func send(_ frame: HUDFrame, to display: Display) async {
    do {
      if let picture = picture(for: frame) {
        dbg("render: \(Self.pageName(frame))")
        // Phone-drawn page: one picture, with the same single whole-card tap
        // target as HUDBuilder (the fallback when Inputs is unavailable).
        try await display.send(MWDATDisplay.FlexBox(direction: .column) {
          MWDATDisplay.Image(image: picture, sizePreset: .fill, cornerRadius: .none)
        }.onTap { [weak self] in
          Task { @MainActor in self?.cardTapped() }
        })
        return
      }
      try await display.send(HUDBuilder.build(frame: frame, onCardTap: { [weak self] in
        Task { @MainActor in self?.cardTapped() }
      }))
    } catch {
      let desc = (error as? DisplayError)?.description ?? error.localizedDescription
      if desc.lowercased().contains("supersed") { return }
      dbg("render error: \(desc)")
      // A timed-out frame is replaced by the next one; no phone banner.
      if desc.lowercased().contains("timed out") { return }
      errorMessage = desc; showError = true
    }
  }


  // MARK: - Voice launch ("Hey Meta, start Matchsight")
  //
  // Meta AI launches or foregrounds the app and sends a LaunchApp invocation,
  // which must be answered exactly once. Needs a Wearables Developer Center
  // project with the app name "Matchsight" (MetaAppID ≠ 0); in Developer
  // Mode the stream simply never delivers.

  private func startVoiceLaunch() {
    guard voiceLaunchStream == nil else { return }
    do {
      let stream = try VoiceInvocationsStream(wearables: wearables)
      voiceLaunchTokens = [
        stream.invocationsPublisher.listen { [weak self] invocation in
          Task { @MainActor in self?.handleVoiceInvocation(invocation) }
        },
        stream.errorPublisher.listen { [weak self] error in
          Task { @MainActor in self?.dbg("voice launch error: \(error.description)") }
        },
      ]
      voiceLaunchStream = stream
      voiceLaunchTask = Task { [weak self] in
        guard let self else { return }
        self.listenForVoiceLaunch(on: self.wearables.devices)
        for await devices in self.wearables.devicesStream() {
          self.listenForVoiceLaunch(on: devices)
        }
      }
    } catch {
      dbg("voice launch unavailable: \(error)")
    }
  }

  /// Listens on the display glasses (start() replaces any earlier device).
  private func listenForVoiceLaunch(on devices: [DeviceIdentifier]) {
    guard let stream = voiceLaunchStream else { return }
    let target = devices.first { wearables.deviceForIdentifier($0)?.supportsDisplay() == true } ?? devices.first
    guard let target else { return }
    do {
      try stream.start(deviceIdentifier: target)
      dbg("voice launch: listening")
    } catch {
      dbg("voice launch: start failed: \(error)")
    }
  }

  /// "Hey Meta, start Matchsight": bring the HUD back on the score panel.
  private func handleVoiceInvocation(_ invocation: any VoiceInvocation) {
    guard let launch = invocation as? LaunchApp else { return }
    dbg("voice launch: Hey Meta, start Matchsight")
    Task {
      _ = await launch.responseHandle.sendSuccess(actionOutput: nil)
    }
    Task { [weak self] in
      guard let self else { return }
      await self.reactivateHUD()
      self.appModel?.hudInput(.home)
    }
  }

  // MARK: - Phone-drawn pages (ImageHUD)

  /// Every page is drawn on the phone (see ImageHUD); HUDBuilder's DSL layout
  /// is the fallback when a drawing fails. Crests and headshots load in the
  /// background and the page redraws when they land.
  private func picture(for frame: HUDFrame) -> UIImage? {
    let redraw: @MainActor () -> Void = { [weak self] in
      guard let self, let f = self.currentFrame else { return }
      Task { await self.render(f) }
    }
    let photoURL: (Int) -> URL? = { PlayerPhoto.url(playerId: $0).flatMap(URL.init(string:)) }
    let photos: (Int) -> UIImage? = { [remoteImages] id in remoteImages.image(photoURL(id)) }
    // Compact scoreboard for the deck pages (crests load like any other image).
    var score: CompactScore?
    if let s = appModel?.scoreSummary {
      remoteImages.prefetch([s.homeCrestURL, s.awayCrestURL], onLoad: redraw)
      score = CompactScore(summary: s, homeCrest: remoteImages.image(s.homeCrestURL),
                           awayCrest: remoteImages.image(s.awayCrestURL))
    }
    if appModel?.hudStyle == .darkGlass, let picture = darkPicture(for: frame, score: score, photos: photos) {
      return picture
    }
    switch frame.body {
    case let .panel(p):
      remoteImages.prefetch([p.homeCrestURL, p.awayCrestURL], onLoad: redraw)
      return ImageHUD.scorePanel(p, toast: frame.toast, deck: frame.deck,
                                 homeCrest: remoteImages.image(p.homeCrestURL),
                                 awayCrest: remoteImages.image(p.awayCrestURL))
    case let .playerCard(card):
      guard let appModel, let xi = appModel.currentXI, appModel.currentPlayerIndex >= 1 else { return nil }
      let index = min(appModel.currentPlayerIndex - 1, xi.count - 1)
      remoteImages.prefetch(xi.map { $0.playerId.flatMap(photoURL) }, onLoad: redraw)
      if card.isDetail {
        let player = xi[index]
        let spot = FormationLayout.spots(xi).first { $0.player == player }
        // The feed has no positional data: heat is simulated, scripted demo only.
        let heat = appModel.isScripted ? spot.map { SimulatedHeat.points(for: $0) } : nil
        return ImageHUD.playerDetail(player: player, photo: player.playerId.flatMap(photos),
                                     stats: player.playerId.flatMap { appModel.playerStats[$0] },
                                     spot: spot, heat: heat, scripted: appModel.isScripted,
                                     teamLine: card.teamLine, counter: card.counter, toast: frame.toast,
                                     deck: frame.deck)
      }
      return ImageHUD.carousel(xi: xi, index: index, teamLine: card.teamLine, counter: card.counter,
                               toast: frame.toast, deck: frame.deck, photos: photos, stats: appModel.playerStats)
    case let .insight(c):
      return ImageHUD.insight(c, toast: frame.toast, score: score, deck: frame.deck)
    case let .events(title, lines), let .stats(title, lines), let .otherLive(title, lines):
      return ImageHUD.list(title: title, lines: lines, toast: frame.toast, score: score,
                           deck: frame.deck)
    case let .lineup(c):
      let xi = appModel?.currentXI
      let crestURL = appModel?.currentXITeam.flatMap { TeamStyle.style(for: $0).crestURL }
      remoteImages.prefetch([crestURL] + (xi ?? []).map { $0.playerId.flatMap(photoURL) }, onLoad: redraw)
      return ImageHUD.roster(c, xi: xi, crest: remoteImages.image(crestURL), photos: photos,
                             stats: appModel?.playerStats ?? [:], toast: frame.toast, deck: frame.deck)
    case let .takeover(t):
      let url = t.imageURL.flatMap(URL.init(string:))
      remoteImages.prefetch([url], onLoad: redraw)
      return ImageHUD.takeover(t, photo: remoteImages.image(url), score: score)
    case let .intro(i):
      remoteImages.prefetch([i.homeCrestURL, i.awayCrestURL], onLoad: redraw)
      return ImageHUD.intro(i, homeCrest: remoteImages.image(i.homeCrestURL),
                            awayCrest: remoteImages.image(i.awayCrestURL))
    case let .message(text):
      return ImageHUD.message(text, toast: frame.toast, score: score, deck: frame.deck)
    case let .quiet(q):
      return ImageHUD.quiet(q)
    case let .guide(g):
      return ImageHUD.guide(g, toast: frame.toast)
    }
  }


  /// Dark glass pages; nil for the bodies that keep their classic look
  /// (goal banners, the crest intro, messages, the quiet page).
  private func darkPicture(for frame: HUDFrame, score: CompactScore?,
                           photos: @escaping (Int) -> UIImage?) -> UIImage? {
    guard let appModel else { return nil }
    let clock = appModel.hudClock
    switch frame.body {
    case let .panel(p):
      return ImageHUD.darkLive(p, latest: appModel.latestEvents, score: score, toast: frame.toast, deck: frame.deck)
    case let .insight(c):
      return ImageHUD.darkStory(c, score: score, clock: clock, toast: frame.toast, deck: frame.deck)
    case .events:
      return ImageHUD.darkEvents(appModel.latestEvents, score: score, clock: clock, toast: frame.toast,
                                 deck: frame.deck)
    case let .stats(title, lines), let .otherLive(title, lines):
      return ImageHUD.darkList(title: title, lines: lines, score: score, clock: clock, toast: frame.toast,
                               deck: frame.deck)
    case let .lineup(c):
      guard let xi = appModel.currentXI, !xi.isEmpty else { return nil }
      let parts = c.title.components(separatedBy: " · ")
      return ImageHUD.darkBoard(xi: xi, focus: nil, teamName: appModel.currentXITeam?.name ?? parts[0],
                                formation: parts.dropFirst().first, score: score, clock: clock,
                                toast: frame.toast, deck: frame.deck)
    case let .playerCard(card):
      guard let xi = appModel.currentXI, appModel.currentPlayerIndex >= 1 else { return nil }
      let index = min(appModel.currentPlayerIndex - 1, xi.count - 1)
      let player = xi[index]
      if card.isDetail {
        return ImageHUD.darkPlayer(player: player, photo: player.playerId.flatMap(photos),
                                   stats: player.playerId.flatMap { appModel.playerStats[$0] },
                                   scripted: appModel.isScripted, counter: card.counter, score: score,
                                   clock: clock, toast: frame.toast, deck: frame.deck)
      }
      let parts = card.teamLine.components(separatedBy: " · ")
      return ImageHUD.darkBoard(xi: xi, focus: index, teamName: appModel.currentXITeam?.name ?? parts[0],
                                formation: parts.dropFirst().first, score: score, clock: clock,
                                toast: frame.toast, deck: frame.deck)
    case .takeover, .intro, .message, .quiet, .guide:
      return nil
    }
  }

  // MARK: - Tap-burst vocabulary (350ms resolve on the single card target)
  //
  // Copied from the mirror app's `mirrorCardTapped` pattern, but resolves to
  // `appModel.tapBurst(count:)` instead of terminal keys. Phase-guarded: taps
  // are ignored when no frame is active (DAT rule #3) so a stale layout's live
  // handler can never fire.

  @ObservationIgnored private var tapCount = 0
  @ObservationIgnored private var tapResolveTask: Task<Void, Never>?

  @ObservationIgnored private var lastRawTap: Date?

  func cardTapped() {
    guard currentFrame != nil else { dbg("card tap ignored (no active frame)"); return }
    let now = Date()
    let gap = lastRawTap.map { Int(now.timeIntervalSince($0) * 1000) }
    lastRawTap = now
    dbg("raw tap (+\(gap.map(String.init) ?? "–") ms since previous)")
    tapCount += 1
    tapResolveTask?.cancel()
    tapResolveTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard let self, !Task.isCancelled, self.currentFrame != nil else { return }
      let count = self.tapCount
      self.tapCount = 0
      self.dbg("tap burst → \(count)")
      self.appModel?.tapBurst(count: count)
    }
  }

  // MARK: - Session lifecycle (carried over verbatim from AgentViewModel)

  private func startSessionIfNeeded() async {
    guard session == nil, registrationState == .registered else { return }
    requiresDATAppUpdate = false

    lastStatus = "Looking for your glasses…"; connPhase = .pairing
    await waitForDisplayDevice(timeoutMs: 20000)

    for connectAttempt in 1...5 {
      lastStatus = connectAttempt == 1 ? "Connecting…" : "Connecting… (attempt \(connectAttempt)/5)"
      connPhase = .pairing

      var devSession: DeviceSession?
      var sawStaleSession = false
      for attempt in 1...10 {
        do { devSession = try wearables.createSession(deviceSelector: deviceSelector); break }
        catch DeviceSessionError.noEligibleDevice {
          lastStatus = "Waiting for glasses (\(attempt)/10)…"
          try? await Task.sleep(for: .milliseconds(1500)); continue
        } catch DeviceSessionError.sessionAlreadyExists {
          sawStaleSession = true
          lastStatus = "Glasses busy from a previous session — fold & reopen them (\(attempt)/10)…"
          try? await Task.sleep(for: .seconds(2)); continue
        } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
          requiresDATAppUpdate = true
          showError("DAT app on glasses needs updating."); return
        } catch { showError("Failed to create session: \(error.localizedDescription)"); return }
      }
      guard let devSession else {
        showError(sawStaleSession
          ? "A session from a previous launch is still active. Fold your glasses closed, wait a few seconds, reopen them, then try again."
          : "No eligible device. Re-pair and try again.")
        return
      }
      session = devSession
      sessionStateTask = Task { [weak self] in
        guard let self else { return }
        for await s in devSession.stateStream() {
          self.dbg("session state → \(s)")
          switch s {
          case .started: await self.onSessionStarted(devSession)
          case .stopping, .stopped: await self.onSessionStopped()
          default: break
          }
        }
      }
      sessionErrorTask = Task { [weak self] in
        guard let self else { return }
        for await err in devSession.errorStream() { self.handleSessionError(err) }
      }

      do { try devSession.start() }
      catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
        requiresDATAppUpdate = true; showError("DAT app on glasses needs updating."); return
      }
      catch { showError("Failed to start session: \(error.localizedDescription)"); return }

      if await waitForSessionStarted(devSession, timeoutMs: 8000) {
        return
      }

      lastStatus = "Glasses didn't respond — retrying…"
      await teardown()
      try? await Task.sleep(for: .milliseconds(800))
    }

    showError("Couldn't connect to the glasses. Make sure they're on and connected in the Meta AI app, then tap Reactivate HUD.")
  }

  private func waitForSessionStarted(_ devSession: DeviceSession, timeoutMs: Int) async -> Bool {
    var waited = 0
    while waited < timeoutMs {
      if devSession.state == .started { return true }
      try? await Task.sleep(for: .milliseconds(250)); waited += 250
    }
    return devSession.state == .started
  }

  private func waitForDisplayDevice(timeoutMs: Int) async {
    var waited = 0
    while waited < timeoutMs {
      let hasDisplay = wearables.devices.contains { id in
        wearables.deviceForIdentifier(id)?.supportsDisplay() == true
      }
      if hasDisplay { return }
      try? await Task.sleep(for: .milliseconds(400)); waited += 400
    }
  }

  private func onSessionStarted(_ devSession: DeviceSession) async {
    requiresDATAppUpdate = false
    lastStatus = "Session started · setting up display"
    dbg("session started; adding display")
    do {
      let d = try devSession.addDisplay()
      display = d
      installDisplayListener(d)
      d.start()   // DAT ≥ 0.8: synchronous
      startInputs(devSession)
      appModel?.glassesSessionStarted()
      listenForVoiceLaunch(on: wearables.devices)   // the channel needs the link up
    } catch {
      lastStatus = "Display failed: \(error.localizedDescription)"
      dbg("addDisplay/start failed: \(error)")
    }
  }

  private func onSessionStopped() async {
    cancelHold()
    display = nil; displayStateToken = nil
    displayAsleep = false; wakeStartedAt = nil
    resetInputsRearm(); dropInputs()
    if connPhase != .unregistered { connPhase = .pairing }
    lastStatus = sessionEndReason ?? "Disconnected"
    sessionEndReason = nil
  }

  private func installDisplayListener(_ display: Display) {
    displayStateToken = display.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.dbg("display state → \(state)")
        switch state {
        case .started:
          if let since = self.wakeStartedAt {
            self.wakeStartedAt = nil
            self.dbg("battery saver: display back in \(String(format: "%.1f", Date().timeIntervalSince(since))) s")
          }
          self.connPhase = .ready
          self.lastStatus = "Connected · ready"
          // Reconnect recovery: re-render current state so no stale layout
          // (with live tap handlers) lingers on the glasses (spec Error handling).
          if let appModel = self.appModel {
            await appModel.handleGlassesReady()
          } else if let frame = self.currentFrame {
            await self.render(frame)
          }
        case .stopped:
          self.lastStatus = self.displayAsleep ? "Display off · battery saver"
                                               : "HUD dormant — tap Reactivate HUD"
        default: break
        }
      }
    }
  }

  func reactivateHUD() async {
    appModel?.wakeHUD()
    // Swipes lost and the automatic re-arm gave up: try once more.
    if let session, session.state == .started, inputs?.state != .active, inputsRearmTask == nil {
      dbg("inputs: re-arm from Reactivate HUD")
      dropInputs()
      startInputs(session)
    }
    let alive = (session != nil) && (session?.state == .started)
    if !alive { lastStatus = "Reconnecting…"; await teardown(); await startSessionIfNeeded(); return }
    if let display, display.state == .started {
      if let frame = currentFrame { await render(frame) }
      return
    }
    if let display { display.start(); return }
    guard let devSession = session else { return }
    do {
      let d = try devSession.addDisplay(); display = d; installDisplayListener(d); d.start()
    } catch { await teardown(); await startSessionIfNeeded() }
  }

  func disconnect() async {
    isDisconnecting = true
    appModel?.glassesDisconnectedByUser()
    await teardown()
    connPhase = registrationState == .registered ? .pairing : .unregistered
    currentFrame = nil
    try? await Task.sleep(for: .milliseconds(500)); isDisconnecting = false
  }

  private func handleSessionError(_ error: DeviceSessionError) {
    dbg("session error: \(error)")
    if isDisconnecting { return }
    switch error {
    case .insufficientSDKVersion:
      // DAT 1.0: terminal — the glasses no longer support this app's SDK.
      showError("Your glasses need a newer Matchsight build (its glasses SDK is too old).")
      return
    case .dwaOutOfStuRange:
      // DAT 1.0: non-blocking compatibility warning — keep running.
      lastStatus = "Glasses or Meta AI app update recommended"
      return
    case .batteryCritical:
      sessionEndReason = "Glasses battery critical"
      showError("Your glasses' battery is critically low. Charge them to keep watching.")
      return
    case .peakPowerShutdown:
      sessionEndReason = "Glasses shut down (power)"
      showError("Your glasses shut down to protect the battery. Charge them, then tap Reactivate HUD.")
      return
    case .thermalCritical, .thermalEmergency:
      sessionEndReason = "Glasses too hot"
      showError("Your glasses are too hot. Let them cool down, then tap Reactivate HUD.")
      return
    case let .unexpectedError(description) where description.lowercased().contains("ended by device"):
      // What a flat battery looked like on 2026-10-28: no batteryCritical first.
      // It often reconnects by itself; only say so if it stays down.
      sessionEndReason = "Glasses ended the session"
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(15))
        guard let self, self.connPhase != .ready, !self.isDisconnecting else { return }
        self.showError("Your glasses ended the session. The battery may be flat, or they were folded or out of range. Tap Reactivate HUD when they're back.")
      }
      return
    default:
      break
    }
    let d = error.localizedDescription.lowercased()
    if d.contains("session ended") || d.contains("sessionended") { return }
    showError(error.localizedDescription)
  }

  // MARK: - Registration helpers (verbatim)

  func startRegistration() async {
    do { try await wearables.startRegistration() } catch { showError(error.localizedDescription) }
  }
  func openDATAppUpdate() async {
    do { try await wearables.openDATGlassesAppUpdate() } catch { showError(error.localizedDescription) }
  }
  func startUnregistration() async {
    do { try await wearables.startUnregistration() } catch { showError(error.localizedDescription) }
  }

  private func startInputs(_ devSession: DeviceSession) {
    guard inputs == nil else { return }
    do {
      // consumeBack: false — observe only; the system back gesture still works.
      guard let i = try devSession.addInputs(configuration: InputsConfiguration(consumeBack: false)) else {
        dbg("inputs: addInputs returned nil"); return
      }
      inputs = i
      inputsStateToken = i.statePublisher.listen { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          self.dbg("inputs state → \(state)")
          if state == .active, self.inputsRearmAttempts > 0 {
            self.dbg("inputs: re-armed")
            self.inputsRearmAttempts = 0
          }
          if state == .inactive, self.inputs === i { self.inputsWentInactive() }
        }
      }
      inputsErrorToken = i.errorPublisher.listen { [weak self] error in
        Task { @MainActor in self?.dbg("inputs error: \(error)") }
      }
      inputsTask = Task { [weak self] in
        for await event in i.events {
          self?.handleInput(event)
        }
      }
    } catch {
      dbg("inputs: addInputs failed: \(error)")
    }
  }

  // MARK: - Inputs re-arm
  //
  // Seen on hardware (2026-10-28): Inputs went inactive on its own while the
  // session and display kept running, and never came back, so swipes died
  // until the app restarted (pinch still worked through the display's tap).
  // Add a fresh Inputs after 1 s, 3 s and 10 s; a whole-session drop
  // already recovers through the session lifecycle and is left alone.

  static let inputsRearmDelays: [Duration] = [.seconds(1), .seconds(3), .seconds(10)]
  /// Stops a tug of war if the glasses keep switching Inputs off on purpose.
  static let maxInputsRearmsPerSession = 10

  private func inputsWentInactive() {
    guard inputsRearmTask == nil, !isDisconnecting else { return }
    inputsRearmTask = Task { [weak self] in
      guard let self else { return }
      defer { self.inputsRearmTask = nil }
      while self.inputsRearmAttempts < Self.inputsRearmDelays.count {
        try? await Task.sleep(for: Self.inputsRearmDelays[self.inputsRearmAttempts])
        guard !Task.isCancelled else { return }
        guard let session = self.session, session.state == .started, self.display != nil,
              !self.isDisconnecting else {
          self.dbg("inputs: not re-arming, the session is ending"); return
        }
        if self.inputs?.state == .active || self.inputs?.state == .activating { return }
        guard self.inputsRearmsThisSession < Self.maxInputsRearmsPerSession else {
          self.dbg("inputs: re-arm limit reached this session"); break
        }
        self.inputsRearmAttempts += 1
        self.inputsRearmsThisSession += 1
        self.dbg("inputs: re-arm \(self.inputsRearmAttempts)/\(Self.inputsRearmDelays.count)")
        // DAT 1.0.1 has no removeCapability: release the dropped Inputs and
        // add a fresh one (addInputs logs it if the SDK refuses).
        self.dropInputs()
        self.startInputs(session)
        try? await Task.sleep(for: .seconds(3))
        if self.inputs?.state == .active { return }
      }
      self.dbg("inputs: gave up re-arming")
      self.showError("Swipes stopped working on the glasses. Tap Reactivate HUD to bring them back.")
    }
  }

  private func dropInputs() {
    inputsTask?.cancel(); inputsTask = nil
    inputsStateToken = nil; inputsErrorToken = nil; inputs = nil
  }

  private func resetInputsRearm() {
    inputsRearmTask?.cancel(); inputsRearmTask = nil
    inputsRearmAttempts = 0; inputsRearmsThisSession = 0
  }

  // MARK: - Gesture mapping (Inputs → HUD / voice)

  /// Measured on hardware (2026-10-26): quick pinches are held 80–175 ms and
  /// are followed by `select`; deliberate holds (1.2 s, 2.25 s) produce
  /// drag down…up with no `select`.
  static let holdThreshold: Duration = .milliseconds(400)

  @ObservationIgnored private var holdTask: Task<Void, Never>?
  @ObservationIgnored private var isHolding = false
  /// A `select` right after a hold's release belongs to the hold — ignore it.
  @ObservationIgnored private var holdEndedAt: Date?

  /// Raw-event trace for diagnosing missed swipes: one line per event, with
  /// drag moves folded into a single summary at drag up.
  @ObservationIgnored private var dragTrace: (startMs: Int64, x: Float, y: Float, sumDx: Float, sumDy: Float, moves: Int)?

  private func traceRaw(_ event: InputEvent) {
    let guarded = currentFrame == nil ? " [no frame, dropped]" : ""
    switch event {
    case .nav(let direction, let source, let ts):
      dbg("raw nav \(direction) src=\(source) t=\(ts)\(guarded)")
    case .select(let source, let ts):
      dbg("raw select src=\(source) t=\(ts)\(guarded)")
    case .back(let source, let ts):
      dbg("raw back src=\(source) t=\(ts)\(guarded)")
    case .drag(let action, let x, let y, let dx, let dy, let source, let ts):
      switch action {
      case .down:
        dragTrace = (ts, x, y, 0, 0, 0)
        dbg("raw drag down src=\(source) x=\(x) y=\(y) t=\(ts)\(guarded)")
      case .move:
        dragTrace?.sumDx += dx; dragTrace?.sumDy += dy; dragTrace?.moves += 1
      case .up:
        if let d = dragTrace {
          dbg("raw drag up src=\(source) \(ts - d.startMs)ms moves=\(d.moves) Δx=\(x - d.x) Δy=\(y - d.y) Σdx=\(d.sumDx) Σdy=\(d.sumDy)\(guarded)")
        } else {
          dbg("raw drag up src=\(source) (no down) t=\(ts)\(guarded)")
        }
        dragTrace = nil
      }
    default:
      dbg("raw \(event)\(guarded)")
    }
  }

  private func handleInput(_ event: InputEvent) {
    traceRaw(event)
    guard currentFrame != nil else { return }   // phase guard (DAT rule #3)
    switch event {
    case .select:
      if let ended = holdEndedAt, Date().timeIntervalSince(ended) < 0.3 { return }
      dbg("input → select (pinch)")
      appModel?.hudInput(.select)
    case .nav(let direction, _, _):
      switch direction {
      case .right: dbg("input → next (swipe)"); appModel?.hudInput(.next)
      case .left: dbg("input → previous (swipe)"); appModel?.hudInput(.previous)
      case .up: dbg("input → home (swipe)"); appModel?.hudInput(.home)
      case .down: dbg("input → insight (swipe)"); appModel?.hudInput(.insight)
      }
    case .drag(let action, _, _, _, _, _, _):
      switch action {
      case .down:
        guard !isHolding else { return }   // already listening
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self] in
          try? await Task.sleep(for: Self.holdThreshold)
          guard let self, !Task.isCancelled, self.inputs != nil else { return }
          self.isHolding = true
          self.dbg("input → hold began (voice)")
          self.appModel?.voiceHoldBegan()
        }
      case .up:
        holdTask?.cancel(); holdTask = nil
        if isHolding {
          isHolding = false
          holdEndedAt = Date()
          dbg("input → hold ended (voice)")
          Task { await appModel?.voiceHoldEnded() }
        }
      case .move:
        break
      }
    case .back:
      // Thumb + middle-finger pinch: the glasses' own back gesture. The
      // system leaves the app on it, so it is only logged — it explains a
      // "Session ended by device" that follows.
      dbg("input → back (system gesture)")
    default:
      break
    }
  }

  /// The session ended mid-hold, so no `drag.up` will come: stop listening.
  private func cancelHold() {
    holdTask?.cancel(); holdTask = nil
    holdEndedAt = nil
    guard isHolding else { return }
    isHolding = false
    dbg("input → hold cancelled (session ended)")
    Task { await appModel?.voiceHoldCancelled() }
  }

  private func teardown() async {
    cancelHold()
    resetInputsRearm(); dropInputs()
    displayStateToken = nil
    if let display { display.stop() }; display = nil
    sessionStateTask?.cancel(); sessionStateTask = nil
    sessionErrorTask?.cancel(); sessionErrorTask = nil
    session?.stop(); session = nil
  }

  // MARK: - Glasses camera (look at a player)

  enum PhotoFailure: Error, CustomStringConvertible {
    case notConnected, permissionDenied, unavailable(String), timedOut
    var description: String {
      switch self {
      case .notConnected: return "glasses not connected"
      case .permissionDenied: return "camera permission denied"
      case .unavailable(let why): return why
      case .timedOut: return "no photo after 20 s"
      }
    }
  }

  @ObservationIgnored private var cameraTokens: [any AnyListenerToken] = []
  @ObservationIgnored private var takingPhoto = false

  /// One photo from the glasses camera. The camera joins the running session
  /// only for this photo and is detached afterwards; on hardware the display
  /// and the band carried on undisturbed. Never blocks rendering or input.
  func takePhoto(resolution: PhotoResolution = .medium) async -> Result<Data, PhotoFailure> {
    guard let devSession = session, display != nil else { return .failure(.notConnected) }
    guard !takingPhoto else { return .failure(.unavailable("camera busy")) }
    takingPhoto = true
    defer { takingPhoto = false }
    let t0 = Date()
    func log(_ s: String) { dbg("camera +\(Int(Date().timeIntervalSince(t0) * 1000))ms: \(s)") }
    do {
      var status = try await wearables.checkPermissionStatus(.camera)
      if status != .granted {
        status = try await wearables.requestPermission(.camera)
        log("requested permission → \(status)")
      }
      guard status == .granted else { return .failure(.permissionDenied) }
    } catch {
      log("permission error \(error)"); return .failure(.unavailable("camera permission error"))
    }
    let camera: Camera
    do {
      guard let c = try devSession.addCamera() else { log("addCamera returned nil"); return .failure(.unavailable("camera unavailable")) }
      camera = c
    } catch {
      log("addCamera failed: \(error)"); return .failure(.unavailable("camera unavailable"))
    }
    enum Event { case ready, nudge, photo(Data), error(String), timeout }
    let (events, sink) = AsyncStream<Event>.makeStream()
    cameraTokens = [
      camera.photo.statePublisher.listen { if $0 == .started { sink.yield(.ready) } },
      camera.photo.errorPublisher.listen { sink.yield(.error("\($0)")) },
      camera.photo.photoDataPublisher.listen { sink.yield(.photo($0.imageData)) },
    ]
    camera.photo.start()
    // If "started" never arrives, try anyway after 5 s; give up after 20 s.
    let nudge = Task { try? await Task.sleep(for: .seconds(5)); sink.yield(.nudge) }
    let timeout = Task { try? await Task.sleep(for: .seconds(20)); sink.yield(.timeout) }
    var asked = false
    var result: Result<Data, PhotoFailure> = .failure(.timedOut)
    for await event in events {
      switch event {
      case .ready, .nudge:
        guard !asked else { continue }
        asked = true
        log("capture (\(resolution))")
        camera.photo.capturePhoto(resolution: resolution, quality: .high)
        continue
      case .photo(let data):
        log("photo \(data.count) bytes"); result = .success(data)
      case .error(let why):
        log("error \(why)"); result = .failure(.unavailable("camera error"))
      case .timeout:
        log("timed out"); result = .failure(.timedOut)
      }
      break
    }
    nudge.cancel(); timeout.cancel()
    camera.photo.stop()
    camera.stop()
    cameraTokens = []
    if let frame = currentFrame { await render(frame) }
    return result
  }

  #if DEBUG
  private(set) var cameraTestStatus = ""

  /// Debug: one photo, kept in tmp/camera-test.heic to inspect.
  func cameraTest() async {
    cameraTestStatus = "Taking a photo…"
    switch await takePhoto() {
    case .success(let data):
      try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("camera-test.heic"))
      cameraTestStatus = "Photo received (\(data.count) bytes)"
    case .failure(let why):
      cameraTestStatus = "\(why)"
    }
  }
  #endif

  private func showError(_ message: String) { errorMessage = message; showError = true; lastStatus = message }
  func dismissError() { showError = false }
}

extension GlassesViewModel.ConnPhase {
  static func == (l: GlassesViewModel.ConnPhase, r: GlassesViewModel.ConnPhase) -> Bool {
    switch (l, r) {
    case (.unregistered, .unregistered), (.pairing, .pairing), (.ready, .ready): return true
    case (.error(let a), .error(let b)): return a == b
    default: return false
    }
  }
}
