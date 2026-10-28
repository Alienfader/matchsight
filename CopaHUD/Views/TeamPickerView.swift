import SwiftUI
import CopaHUDCore

/// "Pick your teams": a crest grid per competition. Shown once after pairing
/// (and once for already-paired installs after the update), then from
/// Settings → My teams. Skippable — Done works with zero teams.
struct TeamPickerView: View {
  @Bindable var appModel: AppModel
  var onDone: () -> Void

  private enum League: Int, CaseIterable, Identifiable {
    case premierLeague, championsLeague, germanCup
    var id: Int { rawValue }
    var title: String {
      switch self {
      case .premierLeague: return "Premier League"
      case .championsLeague: return "Champions League"
      case .germanCup: return "DFB-Pokal"
      }
    }
    var apiId: Int {
      switch self {
      case .premierLeague: return ApiFootballFeed.premierLeague
      case .championsLeague: return ApiFootballFeed.championsLeague
      case .germanCup: return ApiFootballFeed.germanCup
      }
    }
  }

  @State private var league: League = .premierLeague
  @State private var clubs: [Int: [Team]] = [:]
  @State private var loading = false
  /// Selected teams by id, so a club in both competitions is one pick.
  @State private var selected: [Int: Team] = [:]
  @State private var showKeySheet = false
  @State private var pastedKey = ""

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

  var body: some View {
    ZStack {
      LinearGradient.appBackground.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 14) {
        Text("Pick your teams")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(.white)
        Text("Matchsight follows them live on your glasses.")
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.6))

        Picker("Competition", selection: $league) {
          ForEach(League.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        content
          .frame(maxHeight: .infinity, alignment: .top)

        SwiftUI.Button {
          appModel.setFavourites(selected.values.sorted { $0.name < $1.name })
          onDone()
        } label: {
          Text(selected.isEmpty ? "Done" : "Done · \(selected.count) team\(selected.count == 1 ? "" : "s")")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.navy900)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.live, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
      }
      .padding(20)
    }
    .task(id: league) { await load(league) }
    .sheet(isPresented: $showKeySheet) {
      ApiKeySheet(
        title: "API-Football Key",
        message: "Paste your x-apisports-key from the API-Football dashboard. Stored in the iOS Keychain on this device only. You can change it later in Settings.",
        placeholder: "x-apisports-key",
        pastedKey: $pastedKey, onSave: {
          if SecretsStore.setApiFootballKey(pastedKey) {
            pastedKey = ""
            appModel.refreshFeed()
            showKeySheet = false
            Task { await load(league, force: true) }
          }
        })
    }
    .onAppear {
      selected = Dictionary(appModel.favourites.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
  }

  @ViewBuilder private var content: some View {
    let list = clubs[league.apiId] ?? []
    if loading && list.isEmpty {
      ProgressView().tint(.white).frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
    } else if list.isEmpty {
      // No key yet (or the club list failed to load): enter it right here —
      // this screen covers Settings on first launch.
      VStack(alignment: .leading, spacing: 12) {
        Text(hasKey ? "Couldn't load clubs. If the key was rejected, change it; otherwise check your connection."
                    : "Matchsight needs your API-Football key to load clubs and live matches.")
          .font(.system(size: 15))
          .foregroundStyle(.white.opacity(0.7))
        HStack(spacing: 20) {
          SwiftUI.Button(hasKey ? "Change API-Football key" : "Enter API-Football key") {
            pastedKey = ""; showKeySheet = true
          }
          if hasKey {
            SwiftUI.Button("Try again") { Task { await load(league, force: true) } }
          }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.actionBlue)
        .buttonStyle(.plain)
      }
      .padding(.top, 20)
    } else {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 10) {
          ForEach(list, id: \.id) { team in cell(team) }
        }
      }
    }
  }

  private func cell(_ team: Team) -> some View {
    let isOn = selected[team.id] != nil
    return SwiftUI.Button {
      if isOn { selected[team.id] = nil } else { selected[team.id] = team }
    } label: {
      VStack(spacing: 6) {
        TeamBadge(team: team, size: 36)
        Text(team.name)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, minHeight: 86)
      .padding(6)
      .background(Color.navy700.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(isOn ? Color.live : .clear, lineWidth: 2))
      .overlay(alignment: .topTrailing) {
        if isOn {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.live).padding(5)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(team.name)\(isOn ? ", selected" : "")")
  }

  private var hasKey: Bool { SecretsStore.apiFootballKey?.isEmpty == false }

  private func load(_ league: League, force: Bool = false) async {
    guard force || (clubs[league.apiId] ?? []).isEmpty else { return }
    loading = true
    clubs[league.apiId] = await appModel.clubs(leagueId: league.apiId)
    loading = false
  }
}
