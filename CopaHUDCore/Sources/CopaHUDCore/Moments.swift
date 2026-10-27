import Foundation

/// A VAR decision, mapped from the feed's raw detail string by MatchEngine.
public enum VarOutcome: Sendable, Equatable {
  case goalOverturned
  case goalStands
  case goalAwarded
  case penaltyConfirmed
  case penaltyCancelled
  case other(String)
}

/// A typed "something happened" emitted by MatchEngine. The HUD composer
/// turns these into takeovers (followed match) or toasts (other matches).
public struct MatchMoment: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case goal(scorer: String?, assist: String?, detail: MatchEvent.GoalDetail)
    case redCard(player: String?, team: Team)
    case penaltyAwarded(team: Team)
    case varDecision(VarOutcome)
    case halfTime
    case fullTime
    /// Goal in a non-followed match. `scorer` is nil until the app's
    /// best-effort enrichment fetch fills it.
    case otherMatchGoal(snapshot: MatchSnapshot, scorer: String?)
  }

  public let fixtureId: Int
  public let kind: Kind
  /// Score AFTER this moment (already corrected for VAR overturns).
  public let score: ScoreLine
  public let minute: Int?
  /// Feed id of the protagonist (scorer / sent-off player) when known —
  /// drives the takeover headshot. Additive, defaults nil.
  public let playerId: Int?

  public init(fixtureId: Int, kind: Kind, score: ScoreLine, minute: Int?,
              playerId: Int? = nil) {
    self.fixtureId = fixtureId
    self.kind = kind
    self.score = score
    self.minute = minute
    self.playerId = playerId
  }
}
