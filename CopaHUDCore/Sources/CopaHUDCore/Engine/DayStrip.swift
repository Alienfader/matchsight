import Foundation

/// The phone's day strip: yesterday, today and the next seven days, each as
/// local midnight, for browsing fixtures by date.
public enum DayStrip {
  public static func days(now: Date, back: Int = 1, ahead: Int = 7,
                          calendar: Calendar = .current) -> [Date] {
    let today = calendar.startOfDay(for: now)
    return (-back...ahead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
  }

  public static func isToday(_ day: Date, now: Date, calendar: Calendar = .current) -> Bool {
    calendar.isDate(day, inSameDayAs: now)
  }
}
