import Foundation

/// The phone's Coming up list: favourites' scheduled matches after today
/// (today's are already on the Today list), by kickoff.
public enum ComingUp {
  public static func list(_ fixtures: [Fixture], now: Date, calendar: Calendar = .current) -> [Fixture] {
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
      return []
    }
    // Only scheduled matches: postponed or cancelled ones have no real date.
    return fixtures
      .filter { $0.status == .notStarted && $0.kickoff >= tomorrow }
      .sorted { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }
  }
}
