import SwiftUI
import CopaHUDCore

/// Today's fixtures: hero card for the followed/first-live match, LIVE NOW
/// section for remaining live matches, then "My teams" (fixtures involving a
/// favourite) and the rest grouped by competition — Premier League, then
/// Champions League. Tap any row to follow it — the followed match drives the
/// HUD on the glasses (and wins over auto-follow until it ends).
struct TodayView: View {
  @Bindable var glasses: GlassesViewModel
  @Bindable var appModel: AppModel
  @State private var searchText = ""
  @State private var expanded: Set<String> = []

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        LinearGradient.appBackground.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 20) {
            dayStrip
            if let banner = appModel.banner {
              ErrorBanner(message: bannerText(banner)) { appModel.dismissBanner() }
            }
            if appModel.isShowingToday {
              if let hero = heroMatch {
                heroCard(hero)
              }
              if !liveNowFiltered.isEmpty {
                liveNowSection
              }
              if appModel.fixtures.isEmpty && liveNowFiltered.isEmpty {
                emptyState
              } else if groupedFixtures.isEmpty && liveNowFiltered.isEmpty && heroMatch == nil {
                noResults
              } else {
                ForEach(groupedFixtures, id: \.label) { group in
                  fixtureGroup(group)
                }
              }
              if !isSearching && !appModel.upcoming.isEmpty {
                comingUpSection
              }
            } else if appModel.isLoadingDay {
              ProgressView().tint(.white).padding(.top, 60)
            } else if appModel.dayFixtures.isEmpty {
              noMatchesOnDay
            } else if groupedFixtures.isEmpty {
              noResults
            } else {
              ForEach(groupedFixtures, id: \.label) { group in
                fixtureGroup(group)
              }
            }
          }
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 32)
        }
        .refreshable { await appModel.refreshSelectedDay() }
      }
      .navigationTitle(appModel.isShowingToday ? "Today" : Self.dayFormatter.string(from: appModel.selectedDay))
      .navigationBarTitleDisplayMode(.large)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                  prompt: "Team or championship")
    }
  }

  // MARK: - Hero Match

  private var heroMatch: MatchSnapshot? {
    guard !isSearching else { return nil }
    if let id = appModel.followedFixtureId,
       let snap = appModel.liveNow.first(where: { $0.fixtureId == id }) {
      return snap
    }
    return appModel.liveNow.first
  }

  @ViewBuilder
  private func heroCard(_ snap: MatchSnapshot) -> some View {
    let isFollowed = appModel.followedFixtureId == snap.fixtureId
    SwiftUI.Button { appModel.follow(fixtureId: snap.fixtureId) } label: {
      ZStack(alignment: .top) {
        // Radial glow overlay
        RadialGradient(
          colors: [Color.actionBlue.opacity(0.20), .clear],
          center: .init(x: 0.5, y: 0),
          startRadius: 0,
          endRadius: 200
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        VStack(spacing: 0) {
          // Top bar: competition + live pill
          HStack {
            Text("🏆 \(appModel.fixtures.first { $0.id == snap.fixtureId }?.competition ?? "Live")")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white.opacity(0.55))
              .tracking(0.4)
            Spacer()
            LivePill(status: snap.status, minute: snap.elapsedMinutes)
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 6)

          // Crests + score
          HStack(alignment: .center) {
            VStack(spacing: 10) {
              TeamBadge(team: snap.home, size: 58)
              Text(snap.home.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 96)
            }
            Spacer()
            HStack(alignment: .center, spacing: 12) {
              Text("\(snap.score.home)")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
              Text("·")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
              Text("\(snap.score.away)")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
            }
            Spacer()
            VStack(spacing: 10) {
              TeamBadge(team: snap.away, size: 58)
              Text(snap.away.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 96)
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 18)

          // Possession bar
          if let poss = snap.possessionHome {
            GradientPossBar(home: poss)
              .padding(.horizontal, 20)
          }

          // Following indicator
          HStack {
            HStack(spacing: 6) {
              Image(systemName: isFollowed ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(isFollowed ? Color.goal : Color.white.opacity(0.35))
              Text(isFollowed ? "Following" : "Tap to follow")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isFollowed ? Color.goal : Color.white.opacity(0.35))
            }
            Spacer()
            if isFollowed {
              Text("Driving your HUD")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 14)
          .padding(.bottom, 18)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(Color.white.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(isFollowed ? Color.yellow.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: - LIVE NOW

  private var liveNowFiltered: [MatchSnapshot] {
    let excluding = heroMatch?.fixtureId
    let base = appModel.liveNow.filter { $0.fixtureId != excluding }
    guard isSearching else { return base }
    let q = searchText.trimmingCharacters(in: .whitespaces)
    return base.filter {
      $0.home.name.localizedCaseInsensitiveContains(q)
        || $0.away.name.localizedCaseInsensitiveContains(q)
    }
  }

  private var liveNowSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionHeader(title: "Live Now", count: liveNowFiltered.count, isLive: true)
      VStack(spacing: 8) {
        ForEach(liveNowFiltered, id: \.fixtureId) { snap in
          matchRow(snap)
        }
      }
    }
  }

  // MARK: - Match Rows

  private func matchRow(_ snap: MatchSnapshot) -> some View {
    let isFollowed = appModel.followedFixtureId == snap.fixtureId
    let homeWin = snap.score.home > snap.score.away
    let awayWin = snap.score.away > snap.score.home
    return SwiftUI.Button {
      appModel.follow(fixtureId: snap.fixtureId)
    } label: {
      HStack(alignment: .center, spacing: 14) {
        // Two-line team column
        VStack(alignment: .leading, spacing: 11) {
          twoLineTeam(snap.home, score: snap.score.home, win: homeWin, losing: awayWin)
          twoLineTeam(snap.away, score: snap.score.away, win: awayWin, losing: homeWin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        // Vertical divider
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).frame(maxHeight: .infinity)

        // Status + star column
        VStack(alignment: .center, spacing: 8) {
          LivePill(status: snap.status, minute: snap.elapsedMinutes)
          Image(systemName: isFollowed ? "star.fill" : "star")
            .font(.system(size: 14))
            .foregroundStyle(isFollowed ? Color.goal : Color.white.opacity(0.30))
        }
        .frame(minWidth: 54)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(isFollowed ? Color.red.opacity(0.16) : Color.white.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(isFollowed ? Color.yellow.opacity(0.45) : Color.alertRed.opacity(0.30), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private func fixtureRow(_ fixture: Fixture) -> some View {
    let isFollowed = appModel.followedFixtureId == fixture.id
    // Only today's matches can be followed: the glasses show the live match.
    let canFollow = appModel.isShowingToday
    return SwiftUI.Button {
      appModel.follow(fixtureId: fixture.id)
    } label: {
      HStack(alignment: .center, spacing: 14) {
        VStack(alignment: .leading, spacing: 11) {
          twoLineTeam(fixture.home, score: nil, win: false, losing: false)
          twoLineTeam(fixture.away, score: nil, win: false, losing: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).frame(maxHeight: .infinity)

        VStack(alignment: .center, spacing: 8) {
          if fixture.status.isFinished {
            Text("FT")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white.opacity(0.45))
          } else if fixture.status.isLive {
            LivePill(status: fixture.status, minute: nil)
          } else {
            Text(Self.timeFormatter.string(from: fixture.kickoff))
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white.opacity(0.90))
              .monospacedDigit()
          }
          if canFollow {
            Image(systemName: isFollowed ? "star.fill" : "star")
              .font(.system(size: 14))
              .foregroundStyle(isFollowed ? Color.goal : Color.white.opacity(0.30))
          }
        }
        .frame(minWidth: 54)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.white.opacity(isFollowed ? 0.10 : 0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(isFollowed ? Color.yellow.opacity(0.45) : Color.white.opacity(0.10), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .disabled(!canFollow)
  }

  private func twoLineTeam(_ team: Team, score: Int?, win: Bool, losing: Bool) -> some View {
    HStack(spacing: 11) {
      TeamBadge(team: team, size: 26)
      Text(team.name)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(losing ? .white.opacity(0.45) : .white)
        .lineLimit(1)
      Spacer()
      if let s = score {
        Text("\(s)")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(losing ? .white.opacity(0.45) : .white)
          .monospacedDigit()
      }
    }
  }

  // MARK: - Championship Groups

  private struct FixtureGroup { let label: String; let fixtures: [Fixture] }
  private static let myTeamsLabel = "My teams"

  private var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func matchesSearch(_ fixture: Fixture, competition: String) -> Bool {
    guard isSearching else { return true }
    let q = searchText.trimmingCharacters(in: .whitespaces)
    return fixture.home.name.localizedCaseInsensitiveContains(q)
      || fixture.away.name.localizedCaseInsensitiveContains(q)
      || competition.localizedCaseInsensitiveContains(q)
  }

  private var groupedFixtures: [FixtureGroup] {
    let shown = appModel.isShowingToday ? appModel.fixtures : appModel.dayFixtures
    let sorted = shown.sorted { $0.kickoff < $1.kickoff }
    var order: [String] = []
    var buckets: [String: [Fixture]] = [:]
    for fixture in sorted {
      let label = fixture.competition ?? "Other matches"
      guard matchesSearch(fixture, competition: label) else { continue }
      if buckets[label] == nil { order.append(label) }
      buckets[label, default: []].append(fixture)
    }
    // Favourites' fixtures get their own pinned group; competitions follow in
    // Premier League → Champions League → anything else order.
    let favourites = Set(appModel.favourites.map(\.id))
    let mine = sorted.filter {
      (favourites.contains($0.home.id) || favourites.contains($0.away.id))
        && matchesSearch($0, competition: $0.competition ?? "Other matches")
    }
    func rank(_ label: String) -> Int {
      if label.localizedCaseInsensitiveContains("premier league") { return 0 }
      if label.localizedCaseInsensitiveContains("champions league") { return 1 }
      return 2
    }
    let mineIds = Set(mine.map(\.id))
    var groups = order.enumerated()
      .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
      .map { FixtureGroup(label: $0.element, fixtures: (buckets[$0.element] ?? []).filter { !mineIds.contains($0.id) }) }
      .filter { !$0.fixtures.isEmpty }
    if !mine.isEmpty { groups.insert(FixtureGroup(label: Self.myTeamsLabel, fixtures: mine), at: 0) }
    return groups
  }

  private func isExpanded(_ group: FixtureGroup) -> Bool {
    isSearching
      || !appModel.isShowingToday
      || expanded.contains(group.label)
      || group.label == Self.myTeamsLabel
      || group.fixtures.contains { $0.status.isLive }
      || group.fixtures.contains { $0.id == appModel.followedFixtureId }
  }

  private func fixtureGroup(_ group: FixtureGroup) -> some View {
    let open = isExpanded(group)
    return VStack(alignment: .leading, spacing: 10) {
      SwiftUI.Button {
        if expanded.contains(group.label) { expanded.remove(group.label) }
        else { expanded.insert(group.label) }
      } label: {
        HStack(spacing: 8) {
          Text(group.label)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
          Text("\(group.fixtures.count)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.08)))
          Spacer()
          Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.35))
        }
      }
      .buttonStyle(.plain)
      if open {
        VStack(spacing: 8) {
          ForEach(group.fixtures) { fixture in
            fixtureRow(fixture)
          }
        }
      }
    }
  }

  // MARK: - Day strip

  /// Yesterday through a week ahead. A dot marks days a favourite plays.
  private var dayStrip: some View {
    let now = Date()
    let days = DayStrip.days(now: now)
    return ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(days, id: \.self) { day in
            dayChip(day, isToday: DayStrip.isToday(day, now: now))
              .id(day)
          }
        }
      }
      .onAppear { proxy.scrollTo(appModel.selectedDay, anchor: .center) }
    }
  }

  private func dayChip(_ day: Date, isToday: Bool) -> some View {
    let selected = Calendar.current.isDate(day, inSameDayAs: appModel.selectedDay)
    return SwiftUI.Button {
      appModel.selectDay(day)
    } label: {
      VStack(spacing: 3) {
        Text(isToday ? "Today" : Self.weekdayFormatter.string(from: day))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(selected ? 0.85 : 0.50))
        Text(Self.dayNumberFormatter.string(from: day))
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.white.opacity(selected ? 1 : 0.80))
          .monospacedDigit()
        Circle()
          .fill(favouritePlays(on: day) ? Color.cyan : Color.clear)
          .frame(width: 5, height: 5)
      }
      .frame(width: 52)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(selected ? 0.16 : 0.05)))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(selected ? Color.cyan.opacity(0.60) : Color.white.opacity(0.10), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isToday ? "Today" : Self.dayFormatter.string(from: day))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func favouritePlays(on day: Date) -> Bool {
    let ids = Set(appModel.favourites.map(\.id))
    guard !ids.isEmpty else { return false }
    return (appModel.fixtures + appModel.upcoming).contains {
      Calendar.current.isDate($0.kickoff, inSameDayAs: day)
        && (ids.contains($0.home.id) || ids.contains($0.away.id))
    }
  }

  private static let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE")
    return f
  }()

  private static let dayNumberFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("d")
    return f
  }()

  // MARK: - Coming up

  private var comingUpSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Coming up")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white.opacity(0.55))
      VStack(spacing: 8) {
        ForEach(appModel.upcoming) { fixture in
          comingUpRow(fixture)
        }
      }
    }
  }

  private func comingUpRow(_ fixture: Fixture) -> some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 11) {
        twoLineTeam(fixture.home, score: nil, win: false, losing: false)
        twoLineTeam(fixture.away, score: nil, win: false, losing: false)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1).frame(maxHeight: .infinity)

      VStack(alignment: .center, spacing: 4) {
        Text(Self.dayFormatter.string(from: fixture.kickoff))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.60))
        Text(Self.timeFormatter.string(from: fixture.kickoff))
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(.white.opacity(0.90))
          .monospacedDigit()
        if let competition = fixture.competition {
          Text(competition)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.40))
            .lineLimit(1).minimumScaleFactor(0.7)
        }
      }
      .frame(minWidth: 72)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .stroke(Color.white.opacity(0.10), lineWidth: 1))
  }

  /// "Sat 1 Nov" in the user's locale.
  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEEdMMM")
    return f
  }()

  // MARK: - Empty / No-results

  private var noResults: some View {
    VStack(spacing: 10) {
      Text("🔍").font(.system(size: 44))
      Text("No matches for \"\(searchText)\"")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
    }
    .padding(.top, 60)
  }

  private var noMatchesOnDay: some View {
    VStack(spacing: 10) {
      Text("📅").font(.system(size: 44))
      Text("No matches on \(Self.dayFormatter.string(from: appModel.selectedDay))")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
      Text("Premier League and Champions League fixtures appear here.")
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    .padding(.top, 60)
    .padding(.horizontal, 24)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Text("⚽").font(.system(size: 44))
      Text("No fixtures yet")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
      Text("Add your API-Football key in Settings, or turn on demo mode to rehearse a scripted match.")
        .font(.system(size: 13))
        .foregroundStyle(.white.opacity(0.6))
        .multilineTextAlignment(.center)
    }
    .padding(.top, 60)
    .padding(.horizontal, 24)
  }

  private func bannerText(_ error: FeedError) -> String {
    switch error {
    case .unauthorized: "API key rejected — check it in Settings."
    case .quotaExceeded: "API request limit reached — try again later."
    case .network(let m): "Network error: \(m)"
    case .decoding(let m): "Couldn't read the feed: \(m)"
    }
  }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
  }()

  /// Thin wrapper kept for call sites that used TodayView.flag(for:).
  static func flag(for name: String) -> String { flagEmoji(for: name) }
}
