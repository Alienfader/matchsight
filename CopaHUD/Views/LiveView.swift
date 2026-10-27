import SwiftUI
import CopaHUDCore

/// Phone-side mirror of the glasses HUD: what the current frame shows, the
/// recent moments, the alert-pause ("cinema mode") toggle, a Reactivate HUD
/// button, and the debug log card.
struct LiveView: View {
  private var recorder: VoiceRecorder { appModel.recorder }
  /// The in-flight start (permission prompt + engine); release awaits it so a
  /// quick tap can't leave the mic running.
  @State private var recordingStart: Task<Void, Never>?
  @Bindable var glasses: GlassesViewModel
  @Bindable var appModel: AppModel

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        LinearGradient.appBackground.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 16) {
            if let banner = appModel.banner {
              ErrorBanner(message: bannerText(banner)) { appModel.dismissBanner() }
            }
            hudCard
            analystCard
            lineupCarouselSection
            controlsCard
            momentsCard
            debugCard
          }
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 32)
        }
      }
      .navigationTitle("Live")
      .navigationBarTitleDisplayMode(.large)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
  }

  // MARK: - HUD mirror

  // MARK: - Starting XI portrait carousel (phone-side)

  @ViewBuilder
  private var lineupCarouselSection: some View {
    if let xi = appModel.currentXI {
      let teamName = appModel.currentXITeamName ?? ""
      VStack(alignment: .leading, spacing: 11) {
        // Header: "STARTING XI" left, crest + team right (design LineupCarousel).
        HStack {
          Text("Starting XI")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.70))
            .tracking(0.4)
            .textCase(.uppercase)
          Spacer()
          if !teamName.isEmpty {
            HStack(spacing: 7) {
              CrestView(team: teamName, size: 20)
              Text(teamName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            }
          }
        }
        .padding(.horizontal, 4)

        // Real horizontal scroll-snap carousel. Tap a card → glasses jump to
        // that player; the gold-ringed card mirrors the glasses' current one.
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
              ForEach(Array(xi.enumerated()), id: \.offset) { idx, player in
                playerTile(player, index: idx)
                  .id(idx)
                  .onTapGesture { appModel.goToPlayer(index: idx) }
              }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .scrollTargetLayout()
          }
          .scrollTargetBehavior(.viewAligned)
          .onChange(of: appModel.currentPlayerIndex) { _, newIdx in
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(newIdx, anchor: .center) }
          }
          .onAppear { proxy.scrollTo(appModel.currentPlayerIndex, anchor: .center) }
        }

        // Dot indicator (design DotCarousel) synced to the glasses player.
        HStack(spacing: 6) {
          Spacer()
          ForEach(0..<xi.count, id: \.self) { i in
            let active = i == appModel.currentPlayerIndex
            Circle()
              .fill(active ? Color.white : Color.white.opacity(0.22))
              .frame(width: active ? 7 : 6, height: active ? 7 : 6)
          }
          Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.currentPlayerIndex)
      }
    }
  }

  /// Full-bleed portrait tile — pixel-matches design PlayerCard.jsx (132×176):
  /// photo/silhouette fills the card, ghost number top-right, bottom scrim,
  /// gold position pill + name overlaid bottom-left, gold-glow ring when active.
  private func playerTile(_ player: LineupPlayer, index: Int) -> some View {
    let isActive = index == appModel.currentPlayerIndex
    let photoURL = PlayerPhoto.url(playerId: player.playerId).flatMap { URL(string: $0) }
    let (first, last) = HUDFormat.splitName(player.name)
    return ZStack(alignment: .bottomLeading) {
      // Base: navy radial gradient (matches design's no-photo placeholder bg).
      RadialGradient(
        colors: [Color.navy500, Color.navy800],
        center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 150
      )
      // Photo (cover, top-anchored) or silhouette.
      if let url = photoURL {
        AsyncImage(url: url) { phase in
          if let img = phase.image {
            img.resizable().aspectRatio(contentMode: .fill)
          } else { silhouette }
        }
      } else {
        silhouette
      }
      // Ghost jersey number, top-right.
      if let num = player.number {
        Text("\(num)")
          .font(.system(size: 40, weight: .bold))
          .foregroundStyle(Color.white.opacity(0.16))
          .monospacedDigit()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(.top, 6).padding(.trailing, 12)
      }
      // Bottom scrim so the name reads over any photo.
      LinearGradient(
        colors: [.clear, Color.navy900.opacity(0.55), Color.navy900.opacity(0.94)],
        startPoint: .top, endPoint: .bottom
      )
      .frame(maxHeight: 109)
      .frame(maxHeight: .infinity, alignment: .bottom)
      // Name + position, overlaid bottom-left.
      VStack(alignment: .leading, spacing: 6) {
        if let pos = HUDFormat.positionLabel(player.position) {
          Text(pos)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.navy900)
            .tracking(0.4)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.goal, in: Capsule())
        }
        VStack(alignment: .leading, spacing: 1) {
          if !first.isEmpty {
            Text(first)
              .font(.system(size: 11))
              .foregroundStyle(Color.white.opacity(0.70))
              .lineLimit(1)
          }
          Text(last)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 11)
    }
    .frame(width: 132, height: 176)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(isActive ? Color.goal : Color.white.opacity(0.12), lineWidth: isActive ? 2 : 1)
    )
    .shadow(color: isActive ? Color.black.opacity(0.45) : .clear, radius: 13, y: 10)
  }

  private var silhouette: some View {
    Image(systemName: "person.fill")
      .font(.system(size: 54))
      .foregroundStyle(Color.white.opacity(0.18))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var hudCard: some View {
    ZStack(alignment: .top) {
      // Cyan glow from top
      RadialGradient(
        colors: [Color.cyan.opacity(0.16), .clear],
        center: .init(x: 0.5, y: 0),
        startRadius: 0,
        endRadius: 160
      )
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

      VStack(alignment: .leading, spacing: 16) {
        // Glasses badge + connection dot
        HStack {
          glasssBadge
          Spacer()
          statusDot("Glasses", on: glasses.connPhase == .ready)
        }

        // Crest score row (if panel showing a live followed match)
        if let snap = followedSnap {
          HStack(alignment: .center) {
            HStack(spacing: 10) {
              TeamBadge(team: snap.home, size: 34)
              Text("\(snap.score.home)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            }
            Spacer()
            Text(snap.home.name == snap.away.name ? "" : (snap.groupLabel ?? ""))
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white.opacity(0.35))
            Spacer()
            HStack(spacing: 10) {
              Text("\(snap.score.away)")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
              TeamBadge(team: snap.away, size: 34)
            }
          }
        } else {
          // Fallback: plain text headline
          Text(frameHeadline)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
          if let sub = frameSubline {
            Text(sub)
              .font(.system(size: 14))
              .foregroundStyle(.white.opacity(0.70))
          }
        }

        // Toast line
        if let toast = appModel.frame.toast {
          HStack(spacing: 8) {
            Text(appModel.alertsPaused ? "🔕" : "⚽")
              .font(.system(size: 13))
            Text(appModel.alertsPaused ? "Toasts muted — Cinema Mode on" : toast)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(appModel.alertsPaused ? .white.opacity(0.45) : .cyan)
              .lineLimit(1)
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(appModel.alertsPaused ? Color.white.opacity(0.04) : Color.cyan.opacity(0.10))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(appModel.alertsPaused ? Color.white.opacity(0.08) : Color.cyan.opacity(0.22), lineWidth: 1)
          )
        }
      }
      .padding(18)
    }
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.white.opacity(0.08))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
    .onTapGesture {
      if appModel.hasTakeover {
        appModel.clearTakeovers()   // tap hudCard → skip all queued alerts
      }
    }
    // Lineup navigation lives on the glasses (pinch ×1 = next, ×2 = back),
    // not on the phone — the carousel below is for browsing / tap-to-select.
    .overlay(alignment: .bottomTrailing) {
      if appModel.hasTakeover {
        Text("Tap to skip")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.white.opacity(0.55))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Capsule().fill(Color.white.opacity(0.10)))
          .padding(12)
      }
    }
  }

  private var glasssBadge: some View {
    HStack(spacing: 7) {
      // Simple glasses glyph built from SF Symbols
      Image(systemName: "eyeglasses")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Color.cyan)
      Text("On Glasses Now")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.cyan)
        .tracking(0.4)
        .textCase(.uppercase)
    }
  }

  private var followedSnap: MatchSnapshot? {
    guard case .panel = appModel.frame.body,
          let id = appModel.followedFixtureId else { return nil }
    return appModel.liveNow.first(where: { $0.fixtureId == id })
  }

  // MARK: - Controls

  private var controlsCard: some View {
    card {
      VStack(spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Cinema Mode")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(.white)
            Text("Mutes cross-match toasts")
              .font(.system(size: 12))
              .foregroundStyle(.white.opacity(0.45))
          }
          Spacer()
          Toggle("", isOn: Binding(
            get: { appModel.alertsPaused },
            set: { _ in appModel.toggleAlertsPaused() }
          ))
          .tint(.actionBlue)
          .labelsHidden()
        }

        Divider().overlay(Color.white.opacity(0.08))

        SwiftUI.Button { Task { await glasses.reactivateHUD() } } label: {
          HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
            Text("Reactivate HUD")
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white.opacity(0.90))
          .padding(.vertical, 12)
          .frame(maxWidth: .infinity)
          .background(Color.actionBlue.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(Color.actionBlue.opacity(0.50), lineWidth: 1)
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - AI Analyst

  private var analystCard: some View {
    VStack(alignment: .leading, spacing: 11) {
      SectionHeader(title: "AI Analyst")
      card {
        VStack(alignment: .leading, spacing: 12) {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(InsightQuestion.presets, id: \.self) { question in
              SwiftUI.Button { appModel.askAnalyst(question) } label: {
                Text(questionLabel(question))
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(.white.opacity(0.90))
                  .padding(.vertical, 10)
                  .frame(maxWidth: .infinity)
                  .background(Color.actionBlue.opacity(0.30),
                              in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              }
              .buttonStyle(.plain)
              .disabled(!appModel.analystReady)
              .opacity(appModel.analystReady ? 1 : 0.4)
            }
          }

          voiceButton

          let state = appModel.insightState
          if let content = state.hudContent {
            VStack(alignment: .leading, spacing: 4) {
              Text(content.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
              Text(content.body)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
              Text(content.footer)
                .font(.system(size: 12))
                .foregroundStyle(Color.cyan)
              if let error = state.lastError {
                Text("AI unavailable — showing match data (\(insightErrorText(error)))")
                  .font(.system(size: 11))
                  .foregroundStyle(Color.goalDeep)
              }
            }
          } else {
            Text(appModel.followedFixtureId == nil
                 ? "Follow a match to get AI insights."
                 : !appModel.analystReady ? "Waiting for match data…"
                 : (state.isUpdating ? "Analyst thinking…" : "AI Analyst warming up…"))
              .font(.system(size: 13))
              .foregroundStyle(.white.opacity(0.45))
          }
        }
      }
    }
  }

  /// Hold to talk → Muse Voice Transcribe → Muse Spark → glasses.
  private var voiceButton: some View {
    let enabled = appModel.voiceAvailable && appModel.analystReady
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
        Text(!appModel.voiceAvailable ? "Voice needs Meta AI (Settings)"
             : recorder.isRecording ? "Listening… release to ask" : "Hold to ask")
      }
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.4))
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
      .background((recorder.isRecording ? Color.alertRed : Color.actionBlue).opacity(enabled ? 0.45 : 0.15),
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .onLongPressGesture(minimumDuration: VoiceRecorder.maxSeconds, maximumDistance: 80,
                          perform: {}, onPressingChanged: { pressing in
        guard enabled else { return }
        if pressing {
          recordingStart = Task { await recorder.start() }
        } else {
          let started = recordingStart
          Task {
            await started?.value
            if let wav = await recorder.stop() { appModel.askByVoice(wav: wav) }
          }
        }
      })
      if let line = recorder.lastError ?? appModel.voiceStatus {
        Text(line)
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.6))
          .lineLimit(2)
      }
    }
  }

  private func questionLabel(_ q: InsightQuestion) -> String {
    switch q {
    case .matchStory: return "Story"
    case .formation: return "Formations"
    case .substitutionImpact: return "Last sub"
    case .playerToWatch: return "Who to watch"
    case .spoken: return "Ask by voice"
    }
  }

  private func insightErrorText(_ e: InsightError) -> String {
    switch e {
    case .unauthorized: return "key rejected"
    case .rateLimited: return "rate limited"
    case .timeout: return "timed out"
    case let .http(code, _): return "HTTP \(code)"
    case .network: return "offline"
    case .malformedResponse: return "bad response"
    case .invalid: return "answer failed grounding check"
    }
  }

  // MARK: - Recent Moments

  private var momentsCard: some View {
    VStack(alignment: .leading, spacing: 11) {
      SectionHeader(title: "Recent Moments")
      card {
        if appModel.lastMoments.isEmpty {
          Text("Nothing yet — moments appear here as they happen.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.50))
        } else {
          VStack(spacing: 0) {
            ForEach(Array(appModel.lastMoments.reversed().enumerated()), id: \.offset) { idx, moment in
              HStack(spacing: 12) {
                Text(momentMinute(moment))
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(.white.opacity(0.55))
                  .monospacedDigit()
                  .frame(minWidth: 36, alignment: .leading)
                ZStack {
                  RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.navy700)
                  Text(momentGlyph(moment))
                    .font(.system(size: 13))
                }
                .frame(width: 30, height: 30)
                Text(momentText(moment))
                  .font(.system(size: 14))
                  .foregroundStyle(.white.opacity(0.90))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .lineLimit(1)
                Text(momentTeam(moment))
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(.white.opacity(0.35))
                  .tracking(0.4)
              }
              .padding(.vertical, 10)
              .padding(.horizontal, 10)
              if idx < appModel.lastMoments.count - 1 {
                Divider().overlay(Color.white.opacity(0.07)).padding(.horizontal, 10)
              }
            }
          }
          .padding(-10) // counteract card padding
          .padding(.horizontal, -6)
        }
      }
    }
  }

  // MARK: - Debug

  private var debugCard: some View {
    card {
      VStack(alignment: .leading, spacing: 6) {
        Text("DEBUG LOG")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.yellow.opacity(0.7))
          .tracking(0.4)
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(Array(glasses.debugLog.enumerated()), id: \.offset) { idx, line in
                Text(line)
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundStyle(.white.opacity(0.8))
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .id(idx)
              }
            }
          }
          .frame(maxHeight: 180)
          .onChange(of: glasses.debugLog.count) { _, _ in
            proxy.scrollTo(glasses.debugLog.count - 1, anchor: .bottom)
          }
        }
      }
    }
  }

  // MARK: - Moment helpers

  private func momentMinute(_ m: MatchMoment) -> String { m.minute.map { "\($0)'" } ?? "–" }

  private func momentGlyph(_ m: MatchMoment) -> String {
    switch m.kind {
    case .goal: return "⚽"
    case .redCard: return "🟥"
    case .penaltyAwarded: return "🎯"
    case .varDecision: return "📺"
    case .halfTime: return "⏸"
    case .fullTime: return "🏁"
    case .otherMatchGoal: return "⚽"
    }
  }

  private func momentText(_ m: MatchMoment) -> String {
    switch m.kind {
    case .goal(let scorer, _, _):   return scorer ?? "Goal — \(m.score.home)·\(m.score.away)"
    case .redCard(let player, _):   return player ?? "Sent off"
    case .penaltyAwarded(let team): return "Penalty to \(team.name)"
    case .varDecision(let outcome): return varText(outcome)
    case .halfTime:                  return "Half-time"
    case .fullTime:                  return "Full-time"
    case .otherMatchGoal(let s, let scorer):
      return "\(s.home.name) \(s.score.home)·\(s.score.away) \(s.away.name)\(scorer.map { " · \($0)" } ?? "")"
    }
  }

  private func momentTeam(_ m: MatchMoment) -> String {
    switch m.kind {
    case .goal:                        return ""
    case .redCard(_, let team):        return String(team.name.prefix(3)).uppercased()
    case .penaltyAwarded(let team):    return String(team.name.prefix(3)).uppercased()
    case .otherMatchGoal(let s, _):    return String(s.home.name.prefix(3)).uppercased()
    default:                            return ""
    }
  }

  // MARK: - Frame description (fallback when no live snap)

  private var frameHeadline: String {
    switch appModel.frame.body {
    case .panel(let p): return "\(p.homeFlag) \(p.homeCode) \(p.score.home) · \(p.score.away) \(p.awayCode) \(p.awayFlag)"
    case .events(let title, _): return title
    case .lineup(let c): return c.title
    case .playerCard(let c):
      let position = c.positionLabel.map { " · \($0)" } ?? ""
      return "\(c.lastName) #\(c.number)\(position) — \(c.teamLine)"
    case .stats(let title, _): return title
    case .otherLive(let title, _): return title
    case .takeover(let t): return t.headline
    case .intro(let i): return "\(i.homeCode) v \(i.awayCode)"
    case .insight(let i): return i.title
    case .message(let m): return m
    }
  }

  private var frameSubline: String? {
    switch appModel.frame.body {
    case .panel(let p):
      var bits = [p.clock]
      if let g = p.groupLabel { bits.append(g) }
      if p.isStale { bits.append("· stale ·") }
      return bits.joined(separator: "  ")
    case .takeover(let t):
      return [t.scoreLine, t.detail].compactMap { $0 }.joined(separator: "  ·  ")
    case .events(_, let lines), .stats(_, let lines), .otherLive(_, let lines):
      return lines.prefix(3).joined(separator: "\n")
    case .lineup(let c):
      return c.rows.prefix(3).joined(separator: "\n")
    case .playerCard(let c):
      return "\(c.dots)  \(c.counter)"
    case .insight(let i):
      return "\(i.body)\n\(i.footer)"
    case .intro(let i):
      return i.competition
    case .message:
      return nil
    }
  }

  // MARK: - Helpers

  private func varText(_ outcome: VarOutcome) -> String {
    switch outcome {
    case .goalOverturned: "Goal overturned"
    case .goalStands: "Goal stands"
    case .goalAwarded: "Goal awarded"
    case .penaltyConfirmed: "Penalty confirmed"
    case .penaltyCancelled: "Penalty cancelled"
    case .other(let s): s
    }
  }

  private func bannerText(_ error: FeedError) -> String {
    switch error {
    case .unauthorized: "API key rejected — check it in Settings."
    case .quotaExceeded: "API request limit reached — try again later."
    case .network(let m): "Network error: \(m)"
    case .decoding(let m): "Couldn't read the feed: \(m)"
    }
  }

  private func statusDot(_ label: String, on: Bool) -> some View {
    HStack(spacing: 5) {
      Circle().fill(on ? Color.live : Color.alertRed.opacity(0.7))
        .frame(width: 8, height: 8)
        .shadow(color: (on ? Color.live : .alertRed).opacity(0.7), radius: 4)
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
    }
  }

  @ViewBuilder private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    content()
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
  }
}
