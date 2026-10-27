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

  var body: some View {
    Group {
      if glasses.registrationState == .registered {
        TabView {
          TodayView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Today", systemImage: "calendar") }
          LiveView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
          SettingsView(glasses: glasses, appModel: appModel)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
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
