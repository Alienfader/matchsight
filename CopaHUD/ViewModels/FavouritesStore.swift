import Foundation
import CopaHUDCore

/// The fan's favourite clubs and whether the team picker has been completed.
/// Plain UserDefaults: picks are preferences, not secrets.
@MainActor
enum FavouritesStore {
  private static let teamsKey = "favouriteTeams"
  private static let pickerDoneKey = "teamPickerDone"

  /// Favourite teams (JSON). Unreadable data decodes to no favourites.
  static var teams: [Team] {
    get {
      guard let data = UserDefaults.standard.data(forKey: teamsKey) else { return [] }
      return (try? JSONDecoder().decode([Team].self, from: data)) ?? []
    }
    set {
      UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: teamsKey)
    }
  }

  /// False until the picker's Done is tapped once — so already-paired
  /// installs see the picker on their first launch after the update.
  static var hasCompletedPicker: Bool {
    get { UserDefaults.standard.bool(forKey: pickerDoneKey) }
    set { UserDefaults.standard.set(newValue, forKey: pickerDoneKey) }
  }

  /// Cached club catalogue per league (the picker's grid), so it opens
  /// instantly and costs no API requests after the first load.
  static func cachedClubs(leagueId: Int) -> [Team]? {
    guard let data = UserDefaults.standard.data(forKey: "clubs-\(leagueId)") else { return nil }
    return try? JSONDecoder().decode([Team].self, from: data)
  }

  static func cacheClubs(_ clubs: [Team], leagueId: Int) {
    UserDefaults.standard.set(try? JSONEncoder().encode(clubs), forKey: "clubs-\(leagueId)")
  }
}
