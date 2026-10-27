import Foundation

// MARK: - Shared feed logic
//
// The event-id synthesis rule and the raw type/detail → MatchEvent.Kind
// mapping are the contract both ApiFootballFeed and MockFeed must obey
// identically, so they live here and nowhere else. Re-polling the same event
// (real feed) and replaying the same scripted event (mock) MUST produce the
// same stable id.

enum EventID {
  /// The stable-id contract from MatchEvent's docs:
  ///   "\(fixtureId)-\(minute)+\(extraMinute ?? 0)-\(teamId)-\(rawType)-\(rawDetail)-\(playerId ?? 0)"
  static func synthesize(fixtureId: Int, minute: Int, extraMinute: Int?,
                         teamId: Int, rawType: String, rawDetail: String,
                         playerId: Int?) -> String {
    "\(fixtureId)-\(minute)+\(extraMinute ?? 0)-\(teamId)-\(rawType)-\(rawDetail)-\(playerId ?? 0)"
  }
}

enum EventKindMapper {
  /// Maps API-Football's `type` + `detail` to a contract Kind. Never throws —
  /// anything unrecognized becomes `.unknown(type:detail:)` so a surprise event
  /// can never break a live match.
  static func kind(type rawType: String, detail rawDetail: String) -> MatchEvent.Kind {
    let type = rawType.trimmingCharacters(in: .whitespaces)
    let detail = rawDetail.trimmingCharacters(in: .whitespaces)

    if type.lowercased().hasPrefix("subst") {
      return .substitution
    }

    switch type {
    case "Goal":
      switch detail {
      case "Normal Goal": return .goal(.normal)
      case "Own Goal": return .goal(.ownGoal)
      case "Penalty": return .goal(.penalty)
      case "Missed Penalty": return .goal(.missedPenalty)
      default: return .goal(.normal)
      }

    case "Card":
      // Order matters: a "Second Yellow card" is a sending-off, not a caution.
      if detail.contains("Red Card") || detail.contains("Second Yellow") {
        return .card(.red)
      }
      if detail.contains("Yellow") {
        return .card(.yellow)
      }
      return .unknown(type: rawType, detail: rawDetail)

    case "Var":
      return .varDecision(detail: rawDetail)

    default:
      return .unknown(type: rawType, detail: rawDetail)
    }
  }
}

// MARK: - Date parsing

enum FeedDate {
  /// API-Football fixture dates are ISO-8601 with an offset,
  /// e.g. "2026-06-11T16:00:00+00:00".
  private static let isoWithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  static func parse(_ string: String) -> Date? {
    iso.date(from: string) ?? isoWithFractional.date(from: string)
  }

  /// Local-calendar YYYY-MM-DD used for the `date=` fixtures query.
  static func yyyymmdd(_ date: Date, timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
}

// MARK: - DTO → contract mapping

extension FixtureDTO {
  func toFixture() -> Fixture {
    Fixture(
      id: fixture.id,
      kickoff: FeedDate.parse(fixture.date) ?? Date(timeIntervalSince1970: TimeInterval(fixture.timestamp ?? 0)),
      home: teams.home.team,
      away: teams.away.team,
      groupLabel: league.round,
      competition: league.competitionLabel,
      venue: fixture.venue?.name,
      status: MatchStatus(short: fixture.status.short))
  }

  /// A snapshot carries no possession; the feed enriches it best-effort.
  func toSnapshot(possessionHome: Int? = nil) -> MatchSnapshot {
    MatchSnapshot(
      fixtureId: fixture.id,
      home: teams.home.team,
      away: teams.away.team,
      score: ScoreLine(home: goals.home ?? 0, away: goals.away ?? 0),
      status: MatchStatus(short: fixture.status.short),
      elapsedMinutes: fixture.status.elapsed,
      possessionHome: possessionHome,
      groupLabel: league.round,
      kickoff: FeedDate.parse(fixture.date) ?? Date(timeIntervalSince1970: TimeInterval(fixture.timestamp ?? 0)))
  }
}

extension EventDTO {
  func toEvent(fixtureId: Int) -> MatchEvent {
    let id = EventID.synthesize(
      fixtureId: fixtureId,
      minute: time.elapsed,
      extraMinute: time.extra,
      teamId: team.id,
      rawType: type,
      rawDetail: detail,
      playerId: player?.id)
    return MatchEvent(
      id: id,
      fixtureId: fixtureId,
      minute: time.elapsed,
      extraMinute: time.extra,
      team: team.team,
      player: player?.name,
      playerId: player?.id,
      assist: assist?.name,
      kind: EventKindMapper.kind(type: type, detail: detail))
  }
}

extension LineupDTO {
  func toLineup(fixtureId: Int) -> Lineup {
    Lineup(
      fixtureId: fixtureId,
      team: team.team,
      formation: formation,
      startXI: startXI.map { slot in
        LineupPlayer(
          name: slot.player.name ?? "",
          number: slot.player.number,
          position: slot.player.pos,
          grid: slot.player.grid,
          playerId: slot.player.id)
      },
      coach: coach?.name)
  }
}

extension StatisticsDTO {
  /// Ball possession for this team as a 0–100 Int, when present.
  var ballPossession: Int? {
    statistics.first { $0.type == "Ball Possession" }?.value.intValue
  }

  private func intStat(_ type: String) -> Int? {
    statistics.first { $0.type == type }?.value.intValue
  }

  private func stringStat(_ type: String) -> String? {
    statistics.first { $0.type == type }?.value.stringValue
  }

  /// Everything the stats deck page renders, from one statistics response item.
  var teamStats: TeamStats {
    TeamStats(
      possession: ballPossession,
      totalShots: intStat("Total Shots"),
      shotsOnGoal: intStat("Shots on Goal"),
      corners: intStat("Corner Kicks"),
      yellowCards: intStat("Yellow Cards"),
      redCards: intStat("Red Cards"),
      expectedGoals: stringStat("expected_goals"))
  }
}

// MARK: - Error classification

enum FeedErrorClassifier {
  /// Turns an API-Football `errors` payload into a typed FeedError.
  static func feedError(for errors: ApiErrors) -> FeedError {
    let text = errors.messages.joined(separator: " ").lowercased()
    if text.contains("request limit") || text.contains("subscription")
      || text.contains("requests") || text.contains("quota") {
      return .quotaExceeded
    }
    if text.contains("token") || text.contains("key") || text.contains("api key")
      || text.contains("unauthorized") || text.contains("not authorized") {
      return .unauthorized
    }
    return .decoding(text.isEmpty ? "unknown API error" : text)
  }
}
