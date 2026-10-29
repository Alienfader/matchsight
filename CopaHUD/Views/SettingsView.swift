import SwiftUI
import UIKit
import CopaHUDCore

struct SettingsView: View {
  @Bindable var glasses: GlassesViewModel
  @Bindable var appModel: AppModel

  @State private var hasKey = SecretsStore.apiFootballKey?.isEmpty == false
  @State private var showKeySheet = false
  @State private var pastedKey = ""
  @State private var hasMetaKey = SecretsStore.metaModelKey?.isEmpty == false
  @State private var showMetaKeySheet = false
  @State private var pastedMetaKey = ""
  @State private var proxyURL = SecretsStore.metaProxyURL ?? ""
  @State private var hasProxyToken = SecretsStore.metaProxyToken?.isEmpty == false
  @State private var showProxyURLSheet = false
  @State private var showProxyTokenSheet = false
  @State private var pastedProxyValue = ""
  @State private var takeover: Double = 8
  @State private var tvDelay: Double = 0
  @State private var lookAtPlayer = false
  @State private var showTVSync = false
  @State private var toastsEnabled = true
  @State private var batterySaver: BatterySaver = .dim
  @State private var hudStyle: AppModel.HUDStyle = .classic
  @State private var voiceReadyWhenLocked = true
  @State private var demoMode = false
  @State private var showTeamPicker = false

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        LinearGradient.appBackground.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 22) {
            // My teams (auto-follow + goal toasts)
            settingsGroup(
              header: "My teams",
              footer: "Matchsight follows these clubs' live matches on your glasses automatically."
            ) {
              ForEach(appModel.favourites, id: \.id) { team in
                settingsRow(last: false) {
                  TeamBadge(team: team, size: 26)
                  Text(team.name)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              settingsRow(last: true) {
                Text(appModel.favourites.isEmpty ? "No teams yet" : "\(appModel.favourites.count) team\(appModel.favourites.count == 1 ? "" : "s")")
                  .font(.system(size: 15))
                  .foregroundStyle(.white.opacity(0.6))
                  .frame(maxWidth: .infinity, alignment: .leading)
                SwiftUI.Button(appModel.favourites.isEmpty ? "Pick" : "Edit") { showTeamPicker = true }
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Color.actionBlue)
                  .buttonStyle(.plain)
              }
            }

            // API-Football key
            settingsGroup(
              header: "API-Football key",
              footer: "Your paid x-apisports-key. Stored in the iOS Keychain on this device only — survives reinstall."
            ) {
              settingsRow(last: true) {
                Image(systemName: hasKey ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                  .font(.system(size: 20))
                  .foregroundStyle(hasKey ? Color.live : Color.goalDeep)
                Text(hasKey ? "Stored in Keychain" : "Not set — live data won't load")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                SwiftUI.Button(hasKey ? "Change" : "Enter") { pastedKey = ""; showKeySheet = true }
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Color.actionBlue)
                  .buttonStyle(.plain)
                Image(systemName: "chevron.right")
                  .font(.system(size: 13, weight: .bold))
                  .foregroundStyle(.white.opacity(0.30))
              }
            }

            // Meta AI key (AI Match Analyst)
            settingsGroup(
              header: "Meta AI key",
              footer: "Meta Model API key for AI Insight and voice questions (Muse Spark). Without it the app runs in mock mode and says so on the glasses. Keychain, this device only."
            ) {
              settingsRow(last: true) {
                Image(systemName: hasMetaKey ? "sparkles" : "exclamationmark.shield.fill")
                  .font(.system(size: 20))
                  .foregroundStyle(hasMetaKey ? Color.live : Color.goalDeep)
                Text(hasMetaKey ? "Stored in Keychain" : "Not set — mock AI")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                SwiftUI.Button(hasMetaKey ? "Change" : "Enter") { pastedMetaKey = ""; showMetaKeySheet = true }
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(Color.actionBlue)
                  .buttonStyle(.plain)
                Image(systemName: "chevron.right")
                  .font(.system(size: 13, weight: .bold))
                  .foregroundStyle(.white.opacity(0.30))
              }
            }

            // AI proxy (recommended for anything beyond local dev)
            settingsGroup(
              header: "AI proxy",
              footer: "Recommended: the AI proxy Worker holds the Meta key so it never ships in the app. Overrides the direct key when both are set."
            ) {
              settingsRow(last: false) {
                Text(proxyURL.isEmpty ? "Proxy URL — not set" : proxyURL)
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .lineLimit(1).truncationMode(.middle)
                  .frame(maxWidth: .infinity, alignment: .leading)
                SwiftUI.Button(proxyURL.isEmpty ? "Enter" : "Change") {
                  pastedProxyValue = proxyURL; showProxyURLSheet = true
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.actionBlue)
                .buttonStyle(.plain)
              }
              settingsRow(last: true) {
                Text(hasProxyToken ? "Proxy token stored in Keychain" : "Proxy token — not set")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                SwiftUI.Button(hasProxyToken ? "Change" : "Enter") {
                  pastedProxyValue = ""; showProxyTokenSheet = true
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.actionBlue)
                .buttonStyle(.plain)
              }
            }

            // Data source
            settingsGroup(
              header: "Data source",
              footer: "Demo mode replays a scripted match for rehearsal instead of calling the live API."
            ) {
              settingsRow(last: true) {
                (Text("Demo mode ") + Text("(scripted match)").foregroundColor(.white.opacity(0.35)))
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $demoMode)
                  .labelsHidden()
                  .tint(Color.actionBlue)
                  .onChange(of: demoMode) { _, new in appModel.setDemoMode(new) }
              }
            }

            // Goal takeover
            settingsGroup(
              header: "Goal takeover",
              footer: "How long a goal / VAR / red-card banner holds on the glasses before returning to the deck."
            ) {
              VStack(spacing: 12) {
                HStack {
                  Text("Takeover duration")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                  Spacer()
                  Text("\(Int(takeover))s")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.cyan)
                    .monospacedDigit()
                }
                Slider(value: $takeover, in: 5...12, step: 1) { editing in
                  if !editing { appModel.setTakeoverSeconds(takeover) }
                }
                .tint(Color.actionBlue)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 14)
            }

            // TV delay
            settingsGroup(
              header: "Watching on TV",
              footer: "Live data often arrives before the TV picture. Hold the score, clock, events and goal banners on the glasses this long, so they never spoil what you are about to see. Streaming apps can be 1–3 minutes behind: set it so the glasses' minute matches the TV."
            ) {
              VStack(spacing: 12) {
                HStack {
                  Text("TV delay")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                  Spacer()
                  Text(tvDelay == 0 ? "Off" : String(format: "%d:%02d", Int(tvDelay) / 60, Int(tvDelay) % 60))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.cyan)
                    .monospacedDigit()
                }
                Slider(value: $tvDelay, in: 0...300, step: 5) { editing in
                  if !editing { appModel.setTVDelay(tvDelay) }
                }
                .tint(Color.actionBlue)
                SwiftUI.Button {
                  showTVSync = true
                } label: {
                  Label("Sync with TV…", systemImage: "tv")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 14)
            }

            // HUD style
            settingsGroup(
              header: "HUD style",
              footer: "Dark glass draws every page in one dark card in the same place, with the score always on top, fewer words and bigger figures. It adds less light over the TV. Goal banners keep their look."
            ) {
              Picker("HUD style", selection: $hudStyle) {
                Text("Classic").tag(AppModel.HUDStyle.classic)
                Text("Dark glass").tag(AppModel.HUDStyle.darkGlass)
              }
              .pickerStyle(.segmented)
              .padding(.horizontal, 12)
              .padding(.vertical, 14)
              .onChange(of: hudStyle) { _, new in appModel.setHUDStyle(new) }
            }

            // Battery saver
            settingsGroup(
              header: "Battery saver",
              footer: "After 20 seconds with no gestures and nothing new, the glasses go quiet. Dim shows only a faint score line. Display off turns the display off. Goals, cards, voice and any gesture bring it back; the first gesture only wakes it."
            ) {
              Picker("Battery saver", selection: $batterySaver) {
                Text("Off").tag(BatterySaver.off)
                Text("Dim").tag(BatterySaver.dim)
                Text("Display off").tag(BatterySaver.displayOff)
              }
              .pickerStyle(.segmented)
              .padding(.horizontal, 12)
              .padding(.vertical, 14)
              .onChange(of: batterySaver) { _, new in appModel.setBatterySaver(new) }
            }

            #if DEBUG
            // Camera test (debug builds only)
            settingsGroup(
              header: "Camera test",
              footer: "Debug: takes one photo with the glasses camera while the display stays on, to check they can run together."
            ) {
              settingsRow(last: true) {
                SwiftUI.Button("Test glasses camera") { Task { await glasses.cameraTest() } }
                  .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(glasses.cameraTestStatus)
                  .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                  .lineLimit(2).multilineTextAlignment(.trailing)
              }
            }
            #endif

            // Voice from the glasses
            settingsGroup(
              header: "Voice",
              footer: "Keeps the microphone ready while the glasses are connected, so pinch-and-hold works with the phone locked. iOS shows the mic indicator meanwhile; nothing is kept until you hold."
            ) {
              settingsRow(last: true) {
                Text("Ask from glasses with phone locked")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $voiceReadyWhenLocked)
                  .labelsHidden()
                  .tint(Color.actionBlue)
                  .onChange(of: voiceReadyWhenLocked) { _, new in appModel.setVoiceReadyWhenLocked(new) }
              }
            }

            // Look at a player (glasses camera)
            settingsGroup(
              header: "Look at a player (experimental)",
              footer: "Hold to ask and say \u{201C}who\u{2019}s this?\u{201D}: the glasses take one photo and the phone reads the shirt number to open that player's card. Works best on a TV close-up; players far away are too small to read. Experimental: slow (5–10 s) and often can't read a number. The photo is read on this phone and never kept or sent anywhere."
            ) {
              settingsRow(last: true) {
                Text("Use the glasses camera")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $lookAtPlayer)
                  .labelsHidden()
                  .tint(Color.actionBlue)
                  .onChange(of: lookAtPlayer) { _, new in appModel.setLookAtPlayer(new) }
              }
            }

            // Other matches
            settingsGroup(
              header: "Other matches",
              footer: "A one-line toast over the panel when another live match scores."
            ) {
              settingsRow(last: true) {
                Text("Cross-match toasts")
                  .font(.system(size: 15))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: $toastsEnabled)
                  .labelsHidden()
                  .tint(Color.actionBlue)
                  .onChange(of: toastsEnabled) { _, new in appModel.setToastsEnabled(new) }
              }
            }
          }
          .padding(.horizontal, 18)
          .padding(.top, 12)
          .padding(.bottom, 32)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.large)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .onAppear { syncFromModel() }
      .sheet(isPresented: $showTVSync, onDismiss: { syncFromModel() }) {
        TVSyncSheet(appModel: appModel)
      }
      .sheet(isPresented: $showProxyURLSheet) {
        ApiKeySheet(
          title: "AI Proxy URL",
          message: "Your Worker URL, e.g. https://copahud-ai.<subdomain>.workers.dev. Leave empty and save to remove.",
          placeholder: "https://copahud-ai.….workers.dev",
          allowEmpty: true,
          pastedKey: $pastedProxyValue, onSave: {
            if SecretsStore.setMetaProxyURL(pastedProxyValue) {
              proxyURL = SecretsStore.metaProxyURL ?? ""
              appModel.refreshInsightService()
              showProxyURLSheet = false
            }
          })
      }
      .sheet(isPresented: $showProxyTokenSheet) {
        ApiKeySheet(
          title: "AI Proxy Token",
          message: "The APP_TOKEN you set on the Worker. Stored in the iOS Keychain on this device only.",
          placeholder: "app token",
          pastedKey: $pastedProxyValue, onSave: {
            if SecretsStore.setMetaProxyToken(pastedProxyValue) {
              pastedProxyValue = ""
              hasProxyToken = SecretsStore.metaProxyToken?.isEmpty == false
              appModel.refreshInsightService()
              showProxyTokenSheet = false
            }
          })
      }
      .sheet(isPresented: $showMetaKeySheet) {
        ApiKeySheet(
          title: "Meta AI Key",
          message: "Paste your Meta Model API key from dev.meta.ai. Stored in the iOS Keychain on this device only.",
          placeholder: "Meta Model API key",
          pastedKey: $pastedMetaKey, onSave: {
            if SecretsStore.setMetaModelKey(pastedMetaKey) {
              pastedMetaKey = ""
              hasMetaKey = SecretsStore.metaModelKey?.isEmpty == false
              appModel.refreshInsightService()
              showMetaKeySheet = false
            }
          })
      }
      .sheet(isPresented: $showKeySheet) {
        ApiKeySheet(
          title: "API-Football Key",
          message: "Paste your x-apisports-key from the API-Football dashboard. Stored in the iOS Keychain on this device only.",
          placeholder: "x-apisports-key",
          pastedKey: $pastedKey, onSave: {
          if SecretsStore.setApiFootballKey(pastedKey) {
            pastedKey = ""
            hasKey = SecretsStore.apiFootballKey?.isEmpty == false
            appModel.refreshFeed()
            showKeySheet = false
          }
        })
      }
      .sheet(isPresented: $showTeamPicker) {
        TeamPickerView(appModel: appModel) {
          FavouritesStore.hasCompletedPicker = true
          showTeamPicker = false
        }
      }
    }
  }

  // MARK: - Settings building blocks (design-system grouped glass cards)

  @ViewBuilder
  private func settingsGroup<C: View>(
    header: String, footer: String, @ViewBuilder content: () -> C
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(header)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white.opacity(0.35))
        .tracking(0.4)
        .textCase(.uppercase)
        .padding(.leading, 6)
      VStack(spacing: 0) { content() }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
      Text(footer)
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.35))
        .lineSpacing(2)
        .padding(.horizontal, 6)
    }
  }

  @ViewBuilder
  private func settingsRow<C: View>(last: Bool, @ViewBuilder content: () -> C) -> some View {
    HStack(spacing: 12) { content() }
      .padding(.horizontal, 12)
      .padding(.vertical, 13)
      .overlay(alignment: .bottom) {
        if !last {
          Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.leading, 12)
        }
      }
  }

  private func syncFromModel() {
    takeover = appModel.config.takeoverSeconds
    tvDelay = appModel.tvDelaySeconds
    lookAtPlayer = appModel.lookAtPlayerEnabled
    toastsEnabled = appModel.config.toastsEnabled
    batterySaver = appModel.config.batterySaver
    hudStyle = appModel.hudStyle
    voiceReadyWhenLocked = appModel.voiceReadyWhenLocked
    demoMode = appModel.demoMode
    hasKey = SecretsStore.apiFootballKey?.isEmpty == false
    hasMetaKey = SecretsStore.metaModelKey?.isEmpty == false
    proxyURL = SecretsStore.metaProxyURL ?? ""
    hasProxyToken = SecretsStore.metaProxyToken?.isEmpty == false
  }
}

/// Sync with TV: pick the next whole minute the TV clock will show, tap the
/// moment it gets there, and the TV delay is set to match.
struct TVSyncSheet: View {
  let appModel: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var tvMinute: Int?
  @State private var message: String?

  var body: some View {
    NavigationStack {
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        let live = appModel.liveClockSeconds()
        VStack(alignment: .leading, spacing: 20) {
          Text("Pick the next whole minute your TV clock will show, then tap the moment it gets there.")
            .font(.subheadline).foregroundStyle(.secondary)
          if let live {
            Text("Live data is at \(Self.clock(live))")
              .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            let minute = tvMinute ?? TVSync.suggestedMinute(liveSeconds: live,
                                                           currentDelay: appModel.tvDelaySeconds)
            Stepper(value: Binding(get: { minute }, set: { tvMinute = $0 }), in: 1...130) {
              Text("TV minute \(minute):00").font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            SwiftUI.Button {
              message = Self.describe(appModel.syncTV(tvMinute: minute))
            } label: {
              Text("Tap at \(minute):00")
                .font(.system(size: 28, weight: .heavy).monospacedDigit()).foregroundStyle(.white)
                .padding(.vertical, 28).frame(maxWidth: .infinity)
                .background(Color.actionBlue, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
          } else {
            Text("Waiting for the match clock. It's ready a minute or so into a half, and not at half-time or in stoppage time.")
              .font(.body)
          }
          if let message {
            Text(message).font(.body.weight(.semibold))
          }
          Spacer()
        }
        .padding(20)
      }
      .navigationTitle("Sync with TV").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { SwiftUI.Button("Done") { dismiss() } } }
    }
  }

  static func clock(_ seconds: TimeInterval) -> String {
    String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
  }

  static func describe(_ outcome: TVSync.Outcome?) -> String {
    switch outcome {
    case .delay(let s)?: return s == 0 ? "Your TV is close to live: no delay needed." : "TV delay set to \(clock(s))."
    case .tvAhead?: return "That minute hasn't happened yet in the live data. Pick an earlier minute."
    case .tooFarBehind?: return "That's more than 5 minutes behind. Pick a later minute."
    case nil: return "The match clock isn't ready. Try again in a minute."
    }
  }
}

struct ApiKeySheet: View {
  let title: String
  let message: String
  let placeholder: String
  /// Lets the user save an empty value (clears the setting).
  var allowEmpty = false
  @Binding var pastedKey: String
  let onSave: () -> Void
  @Environment(\.dismiss) private var dismiss
  @FocusState private var fieldFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.system(size: 20, weight: .bold))
          Text(message)
            .font(.footnote).foregroundStyle(.secondary)
        }
        TextField(placeholder, text: $pastedKey, axis: .vertical)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .textContentType(.oneTimeCode)
          .keyboardType(.asciiCapable)
          .focused($fieldFocused)
          .lineLimit(1...3)
          .padding(14)
          .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
          .font(.system(.body, design: .monospaced))
        SwiftUI.Button {
          if let s = UIPasteboard.general.string { pastedKey = s.trimmingCharacters(in: .whitespacesAndNewlines) }
        } label: {
          Label("Paste from clipboard", systemImage: "doc.on.clipboard")
            .font(.system(size: 14, weight: .medium))
        }
        SwiftUI.Button(action: onSave) {
          Text("Save to Keychain").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .padding(.vertical, 12).frame(maxWidth: .infinity).background(.blue, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!allowEmpty && pastedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Spacer()
      }
      .padding(20).navigationTitle("API Key").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { SwiftUI.Button("Cancel") { dismiss() } } }
      .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fieldFocused = true } }
    }
  }
}
