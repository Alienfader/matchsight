import MWDATCore
import SwiftUI

@main
struct CopaHUDApp: App {
  @State private var glasses: GlassesViewModel
  @State private var appModel: AppModel

  init() {
    do { try Wearables.configure() }
    catch {
      #if DEBUG
      NSLog("[CopaHUD] Wearables configure failed: \(error)")
      #endif
    }
    let glasses = GlassesViewModel(wearables: Wearables.shared)
    let appModel = AppModel()
    appModel.attach(glasses: glasses)   // wires the mutual reference + starts scheduling
    _glasses = State(wrappedValue: glasses)
    _appModel = State(wrappedValue: appModel)
  }

  var body: some Scene {
    WindowGroup { ContentView(glasses: glasses, appModel: appModel) }
  }
}
