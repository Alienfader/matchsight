import Foundation

/// The real `MatchFeed`, talking to API-Football v3 (paid tier).
///
/// - `URLSession` is injected so tests can swap in a `URLProtocol` mock and run
///   with zero network traffic.
/// - `now` is injected so the possession cache is deterministic under test.
/// - The API key lives nowhere but this object (no Keychain in core — the app
///   loads it and passes it in).
public final class ApiFootballFeed: MatchFeed, @unchecked Sendable {
  private let apiKey: String
  /// Competitions to poll; empty = every league (dev feeds).
  private let leagueIds: [Int]
  private let season: Int?

  /// API-Football league ids and the season value (start year) Matchsight uses.
  public static let premierLeague = 39
  public static let championsLeague = 2
  public static let clubSeason = 2026
  /// Champions League round whose fixtures list exactly the league-phase clubs.
  static let leaguePhaseRound = "League Stage - 1"
  private let session: URLSession
  private let now: @Sendable () -> Date

  /// `v3.football.api-sports.io` per the API-Football v3 docs.
  private let baseURL = URL(string: "https://v3.football.api-sports.io")!

  /// Statistics (possession + the stats page) are fetched at most once per
  /// 60s per fixture — one response feeds both. Guarded by `lock`.
  private struct StatsEntry {
    let value: MatchStats?
    let at: Date
  }
  private var statsCache: [Int: StatsEntry] = [:]
  private var playerStatsCache: [Int: (value: [Int: PlayerStats], at: Date)] = [:]
  private var predictionCache: [Int: WinProbability] = [:]
  private let lock = NSLock()

  public init(apiKey: String,
              leagueIds: [Int] = [],
              season: Int? = nil,
              session: URLSession = .shared,
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.apiKey = apiKey
    self.leagueIds = leagueIds
    self.season = season
    self.session = session
    self.now = now
  }

  // MARK: - MatchFeed

  /// One request per league (the API takes a single `league`), run
  /// concurrently and merged by kickoff.
  public func todaysFixtures() async throws -> [Fixture] {
    let date = URLQueryItem(name: "date", value: FeedDate.yyyymmdd(now()))
    guard !leagueIds.isEmpty else {
      let env: ApiResponse<FixtureDTO> = try await get(path: "fixtures", query: [date])
      return env.response.map { $0.toFixture() }
    }
    let fixtures = try await withThrowingTaskGroup(of: [Fixture].self) { group in
      for league in leagueIds {
        group.addTask {
          let env: ApiResponse<FixtureDTO> = try await self.get(
            path: "fixtures", query: [date] + self.leagueSeasonQuery(league))
          return env.response.map { $0.toFixture() }
        }
      }
      return try await group.reduce(into: []) { $0 += $1 }
    }
    return fixtures.sorted { ($0.kickoff, $0.id) < ($1.kickoff, $1.id) }
  }

  public func liveSnapshot(fixtureId: Int) async throws -> MatchSnapshot {
    let env: ApiResponse<FixtureDTO> = try await get(
      path: "fixtures", query: [URLQueryItem(name: "id", value: String(fixtureId))])
    guard let dto = env.response.first else {
      throw FeedError.decoding("no fixture \(fixtureId) in response")
    }
    let stats = await cachedStats(fixtureId: fixtureId, homeTeamId: dto.teams.home.id)
    return dto.toSnapshot(possessionHome: stats?.home.possession)
  }

  public func stats(fixtureId: Int) async throws -> MatchStats? {
    // Home/away orientation needs the fixture's home team id; reuse whatever
    // the cache learned during liveSnapshot polling rather than refetching.
    await cachedStats(fixtureId: fixtureId, homeTeamId: nil)
  }

  /// At most one `fixtures/players` request per fixture per 60 s.
  public func playerStats(fixtureId: Int) async throws -> [Int: PlayerStats] {
    let nowDate = now()
    lock.lock()
    if let cached = playerStatsCache[fixtureId], nowDate.timeIntervalSince(cached.at) < 60 {
      lock.unlock()
      return cached.value
    }
    lock.unlock()
    let env: ApiResponse<PlayersTeamDTO> = try await get(
      path: "fixtures/players", query: [URLQueryItem(name: "fixture", value: String(fixtureId))])
    let value = Dictionary(env.response.flatMap(\.playerStats).map { ($0.playerId, $0) },
                           uniquingKeysWith: { a, _ in a })
    lock.lock()
    playerStatsCache[fixtureId] = (value, nowDate)
    lock.unlock()
    return value
  }

  /// One `predictions` request per fixture; a found prediction is kept.
  public func prediction(fixtureId: Int) async throws -> WinProbability? {
    lock.lock()
    if let cached = predictionCache[fixtureId] { lock.unlock(); return cached }
    lock.unlock()
    let env: ApiResponse<PredictionDTO> = try await get(
      path: "predictions", query: [URLQueryItem(name: "fixture", value: String(fixtureId))])
    let value = env.response.first?.winProbability
    if let value {
      lock.lock(); predictionCache[fixtureId] = value; lock.unlock()
    }
    return value
  }

  public func events(fixtureId: Int) async throws -> [MatchEvent] {
    let env: ApiResponse<EventDTO> = try await get(
      path: "fixtures/events", query: [URLQueryItem(name: "fixture", value: String(fixtureId))])
    return env.response.map { $0.toEvent(fixtureId: fixtureId) }
  }

  public func lineups(fixtureId: Int) async throws -> [Lineup] {
    let env: ApiResponse<LineupDTO> = try await get(
      path: "fixtures/lineups", query: [URLQueryItem(name: "fixture", value: String(fixtureId))])
    return env.response.map { $0.toLineup(fixtureId: fixtureId) }
  }

  public func otherLive() async throws -> [MatchSnapshot] {
    // API-Football filters live fixtures through the `live` param itself
    // (`live=all` or `live=<leagueId>`); `league`/`season` are not valid here.
    let live = leagueIds.isEmpty ? "all" : leagueIds.map(String.init).joined(separator: "-")
    let env: ApiResponse<FixtureDTO> = try await get(
      path: "fixtures", query: [URLQueryItem(name: "live", value: live)])
    return env.response.map { $0.toSnapshot() }
  }

  // MARK: - Club catalogue (team picker)

  /// The league's clubs with code and crest, sorted by name. For the
  /// Champions League only the league-phase clubs: the teams endpoint also
  /// lists qualifying-round sides, so membership comes from round 1's fixtures.
  public func clubs(leagueId: Int) async throws -> [Team] {
    let teamsEnv: ApiResponse<TeamInfoDTO> = try await get(
      path: "teams", query: leagueSeasonQuery(leagueId))
    var clubs = teamsEnv.response.map(\.team.team)
    if leagueId == Self.championsLeague {
      let round: ApiResponse<FixtureDTO> = try await get(
        path: "fixtures",
        query: leagueSeasonQuery(leagueId) + [URLQueryItem(name: "round", value: Self.leaguePhaseRound)])
      let ids = Set(round.response.flatMap { [$0.teams.home.id, $0.teams.away.id] })
      clubs = clubs.filter { ids.contains($0.id) }
    }
    return clubs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  // MARK: - Statistics (best-effort, ≤ 1 fetch / 60s / fixture)

  /// Fetches/caches the full statistics response. `homeTeamId` orients the
  /// home/away pair when known; without it the response order is trusted
  /// (API-Football lists home first).
  private func cachedStats(fixtureId: Int, homeTeamId: Int?) async -> MatchStats? {
    let nowDate = now()

    lock.lock()
    if let cached = statsCache[fixtureId], nowDate.timeIntervalSince(cached.at) < 60 {
      lock.unlock()
      return cached.value
    }
    lock.unlock()

    // Cache miss / stale: fetch once. Failure is never fatal — stats are
    // optional, and we still record the attempt so we honour the 60s budget.
    var value: MatchStats? = nil
    do {
      let env: ApiResponse<StatisticsDTO> = try await get(
        path: "fixtures/statistics",
        query: [URLQueryItem(name: "fixture", value: String(fixtureId))])
      if env.response.count >= 2 {
        let homeDTO: StatisticsDTO
        let awayDTO: StatisticsDTO
        if let homeTeamId, let h = env.response.first(where: { $0.team.id == homeTeamId }) {
          homeDTO = h
          awayDTO = env.response.first { $0.team.id != homeTeamId } ?? env.response[1]
        } else {
          homeDTO = env.response[0]
          awayDTO = env.response[1]
        }
        value = MatchStats(home: homeDTO.teamStats, away: awayDTO.teamStats)
      }
    } catch {
      value = nil
    }

    lock.lock()
    statsCache[fixtureId] = StatsEntry(value: value, at: nowDate)
    lock.unlock()
    return value
  }

  // MARK: - Networking

  private func leagueSeasonQuery(_ league: Int) -> [URLQueryItem] {
    var items = [URLQueryItem(name: "league", value: String(league))]
    if let season { items.append(URLQueryItem(name: "season", value: String(season))) }
    return items
  }

  private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> ApiResponse<T> {
    var components = URLComponents(
      url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    components.queryItems = query.isEmpty ? nil : query
    guard let url = components.url else {
      throw FeedError.network("could not build URL for /\(path)")
    }

    var request = URLRequest(url: url)
    request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
    request.httpMethod = "GET"

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw FeedError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw FeedError.network("non-HTTP response")
    }

    // Non-2xx: prefer the API's own error envelope for classification, then
    // fall back to status-code heuristics.
    guard (200..<300).contains(http.statusCode) else {
      if let env = try? JSONDecoder().decode(ApiResponse<T>.self, from: data), !env.errors.isEmpty {
        throw FeedErrorClassifier.feedError(for: env.errors)
      }
      switch http.statusCode {
      case 401, 403: throw FeedError.unauthorized
      case 429, 499: throw FeedError.quotaExceeded
      default: throw FeedError.network("HTTP \(http.statusCode)")
      }
    }

    let env: ApiResponse<T>
    do {
      env = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
    } catch {
      throw FeedError.decoding(error.localizedDescription)
    }

    // API-Football frequently returns 200 with an `errors` object for auth /
    // quota problems — treat those as hard errors too.
    if !env.errors.isEmpty {
      throw FeedErrorClassifier.feedError(for: env.errors)
    }
    return env
  }
}
