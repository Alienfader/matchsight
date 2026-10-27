import Foundation

// VAR detail-string → outcome mapping.

public extension VarOutcome {
  /// Map a raw feed VAR detail string to a typed outcome.
  ///
  /// Substring matching, checked most-specific first. Note "Penalty cancelled"
  /// is tested before the goal-overturn strings so it never gets swallowed by a
  /// loose "cancelled" match. `.penaltyConfirmed` is what the engine turns into
  /// a `.penaltyAwarded` moment; everything else surfaces as `.varDecision`.
  init(detail: String) {
    if detail.contains("Penalty confirmed") {
      self = .penaltyConfirmed
    } else if detail.contains("Penalty cancelled") {
      self = .penaltyCancelled
    } else if detail.contains("Goal cancelled") || detail.contains("Goal Disallowed") {
      self = .goalOverturned
    } else if detail.contains("Goal confirmed") {
      self = .goalStands
    } else if detail.contains("Goal awarded") {
      self = .goalAwarded
    } else {
      self = .other(detail)
    }
  }
}
