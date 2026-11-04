import MWDATCore
import SwiftUI
import CopaHUDCore

struct ContentView: View {
  @Bindable var glasses: GlassesViewModel
  @Bindable var appModel: AppModel
  @Environment(\.scenePhase) private var scenePhase
  /// The team picker as a setup step: once after pairing, and once for
  /// already-paired installs on their first launch after the update.
  @State private var showTeamPicker = !FavouritesStore.hasCompletedPicker
  @State private var tab = 0

  var body: some View {
    Group {
      if glasses.registrationState == .registered {
        TabView(selection: $tab) {
          TodayView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Today", systemImage: "calendar") }.tag(0)
          LiveView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }.tag(1)
          SettingsView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        // Rebuilt when the style changes, so the phone takes its accents.
        .id(appModel.hudStyle)
        .fullScreenCover(isPresented: $showTeamPicker) {
          TeamPickerView(appModel: appModel) {
            FavouritesStore.hasCompletedPicker = true
            showTeamPicker = false
          }
        }
      } else {
        PairingView(glasses: glasses)
      }
    }
    // Black surfaces: system titles, bars and controls take their dark look,
    // with white (or Dark glass cyan) instead of the system blue.
    .preferredColorScheme(.dark)
    .tint(PhoneLook.glow ? Color.glowCyan : .white)
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active { Task { await glasses.reactivateHUD() } }
    }
    .alert("Error", isPresented: $glasses.showError) {
      SwiftUI.Button("OK") { glasses.dismissError() }
    } message: { Text(glasses.errorMessage) }
    .onOpenURL { url in
      guard
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
      else { return }
      Task {
        do { _ = try await Wearables.shared.handleUrl(url) }
        catch {
          glasses.errorMessage = (error as? RegistrationError)?.description ?? error.localizedDescription
          glasses.showError = true
        }
      }
    }
  }
}
