import XCTest
@testable import CopaHUDCore

/// Exercises `ApiFootballFeed` end-to-end with a `URLProtocol` mock — correct
/// URLs/queries/headers per endpoint, the possession cache budget, and typed
/// error surfacing. Zero real network traffic.
final class ApiFootballFeedTests: XCTestCase {

  // MARK: - URLProtocol mock

  /// Intercepts every request from the injected session. `handler` decides the
  /// response; `requests` records what was asked, in order.
  final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    static func reset() {
      handler = nil
      requests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      MockURLProtocol.requests.append(request)
      guard let handler = MockURLProtocol.handler else {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        return
      }
      do {
        let (response, data) = try handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      } catch {
        client?.urlProtocol(self, didFailWithError: error)
      }
    }

    override func stopLoading() {}
  }

  // MARK: - Fixtures / helpers

  private final class Clock {
    var date: Date
    init(_ date: Date) { self.date = date }
  }

  override func setUp() {
    super.setUp()
    MockURLProtocol.reset()
  }

  override func tearDown() {
    MockURLProtocol.reset()
    super.tearDown()
  }

  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func resourceData(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func ok(_ url: URL?, _ data: Data) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
  }

  /// Default router mapping each endpoint to its recorded fixture file.
  private func installDefaultRouter() {
    MockURLProtocol.handler = { [self] request in
      let url = request.url!
      let path = url.path
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let hasLiveAll = query.contains { $0.name == "live" && $0.value == "all" }

      let resource: String
      if path.hasSuffix("/fixtures/events") {
        resource = "apifootball-events"
      } else if path.hasSuffix("/fixtures/lineups") {
        resource = "apifootball-lineups"
      } else if path.hasSuffix("/fixtures/statistics") {
        resource = "apifootball-statistics"
      } else if path.hasSuffix("/predictions") {
        resource = "apifootball-real-prediction"
      } else if path.hasSuffix("/fixtures/players") {
        resource = "apifootball-real-players"
      } else if path.hasSuffix("/fixtures") {
        if query.contains(where: { $0.name == "id" }) {
          resource = "apifootball-live"
        } else {
          resource = "apifootball-fixtures"   // also serves live=all
        }
      } else {
        throw URLError(.unsupportedURL)
      }
      _ = hasLiveAll
      return ok(url, try resourceData(resource))
    }
  }

  private func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
  }

  // MARK: - todaysFixtures

  func testTodaysFixturesHitsCorrectURLWithDateLeagueSeasonAndKey() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1781193600)) // 2026-06-11 16:00 UTC
    let feed = ApiFootballFeed(apiKey: "SECRET-KEY", leagueIds: [1], season: 2026,
                               session: makeSession(), now: { clock.date })

    let fixtures = try await feed.todaysFixtures()
    XCTAssertEqual(fixtures.count, 2)
    XCTAssertEqual(fixtures.first?.home, Team(id: 6, name: "Brazil"))

    let request = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(request.url?.host, "v3.football.api-sports.io")
    XCTAssertEqual(request.url?.path, "/fixtures")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-apisports-key"), "SECRET-KEY")

    let q = query(request)
    XCTAssertEqual(q["league"], "1")
    XCTAssertEqual(q["season"], "2026")
    // Local-calendar date of `now`.
    XCTAssertEqual(q["date"], FeedDate.yyyymmdd(clock.date))
  }

  func testTodaysFixturesOmitsLeagueWhenNil() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(),
                               now: { Date(timeIntervalSince1970: 0) })
    _ = try await feed.todaysFixtures()
    let q = query(try XCTUnwrap(MockURLProtocol.requests.first))
    XCTAssertNil(q["league"])
    XCTAssertNil(q["season"])
    XCTAssertNotNil(q["date"])
  }

  // MARK: - fixtures(on:)

  func testFixturesOnDateQueriesThatDayPerLeague() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1781193600)) // 2026-06-11 16:00 UTC
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026,
                               session: makeSession(), now: { clock.date })
    let day = clock.date.addingTimeInterval(3 * 86400)

    _ = try await feed.fixtures(on: day)
    XCTAssertEqual(MockURLProtocol.requests.count, 2)
    let queries = MockURLProtocol.requests.map(query)
    XCTAssertEqual(Set(queries.map { $0["league"] ?? "" }), ["39", "2"])
    XCTAssertTrue(queries.allSatisfy { $0["date"] == FeedDate.yyyymmdd(day) && $0["season"] == "2026" })
  }

  func testTodaysFixturesIsFixturesOnNow() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1781193600))
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39], season: 2026,
                               session: makeSession(), now: { clock.date })
    let today = try await feed.todaysFixtures()
    let onNow = try await feed.fixtures(on: clock.date)
    XCTAssertEqual(today, onNow)
  }

  // MARK: - liveSnapshot + endpoints

  func testLiveSnapshotReturnsScoreAndPossession() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(),
                               now: { Date(timeIntervalSince1970: 0) })

    let snap = try await feed.liveSnapshot(fixtureId: 1001)
    XCTAssertEqual(snap.fixtureId, 1001)
    XCTAssertEqual(snap.score, ScoreLine(home: 2, away: 1))
    XCTAssertEqual(snap.status, .secondHalf)
    XCTAssertEqual(snap.elapsedMinutes, 67)
    XCTAssertEqual(snap.possessionHome, 65)   // Brazil 65% from statistics

    // Fixture query carried id=1001.
    let fixtureReq = try XCTUnwrap(MockURLProtocol.requests.first { $0.url?.path == "/fixtures" })
    XCTAssertEqual(query(fixtureReq)["id"], "1001")
  }

  func testEventsEndpointURL() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    let events = try await feed.events(fixtureId: 1001)
    XCTAssertEqual(events.count, 8)
    let req = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(req.url?.path, "/fixtures/events")
    XCTAssertEqual(query(req)["fixture"], "1001")
  }

  func testLineupsEndpointURL() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    let lineups = try await feed.lineups(fixtureId: 1001)
    XCTAssertEqual(lineups.count, 2)
    let req = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(req.url?.path, "/fixtures/lineups")
    XCTAssertEqual(query(req)["fixture"], "1001")
  }

  // MARK: - player stats

  func testPlayerStatsEndpointURLAndMapping() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    let stats = try await feed.playerStats(fixtureId: 1557446)
    XCTAssertEqual(stats.count, 6, "both teams' players, keyed by player id")
    XCTAssertEqual(stats[1146]?.passes, 24)
    XCTAssertEqual(stats[1146]?.shots, 1)
    XCTAssertEqual(stats[1146]?.tackles, 2)
    XCTAssertEqual(stats[1146]?.interceptions, 2)
    let req = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(req.url?.path, "/fixtures/players")
    XCTAssertEqual(query(req)["fixture"], "1557446")
  }

  func testPlayerStatsAreFetchedAtMostOncePerMinute() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(), now: { clock.date })
    _ = try await feed.playerStats(fixtureId: 1557446)
    clock.date += 30
    _ = try await feed.playerStats(fixtureId: 1557446)
    XCTAssertEqual(MockURLProtocol.requests.count, 1, "second call within 60 s is served from cache")
    clock.date += 31
    _ = try await feed.playerStats(fixtureId: 1557446)
    XCTAssertEqual(MockURLProtocol.requests.count, 2)
  }

  func testPredictionEndpointIsFetchedOncePerFixture() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    let p = try await feed.prediction(fixtureId: 1557450)
    XCTAssertEqual(p, WinProbability(home: 45, draw: 45, away: 10))
    _ = try await feed.prediction(fixtureId: 1557450)
    XCTAssertEqual(MockURLProtocol.requests.count, 1, "predictions don't change in play; cached per fixture")
    let req = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(req.url?.path, "/predictions")
    XCTAssertEqual(query(req)["fixture"], "1557450")
  }

  func testOtherLiveFiltersByLeagueViaLiveParam() async throws {
    // API-Football filters live fixtures through the `live` param itself
    // (`live=<leagueId>`); `league`/`season` are not valid alongside `live`.
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [1], season: 2026, session: makeSession())
    let snaps = try await feed.otherLive()
    XCTAssertEqual(snaps.count, 2)
    let req = try XCTUnwrap(MockURLProtocol.requests.first)
    XCTAssertEqual(req.url?.path, "/fixtures")
    let q = query(req)
    XCTAssertEqual(q["live"], "1")
    XCTAssertNil(q["league"])
    XCTAssertNil(q["season"])
  }

  func testOtherLiveUsesLiveAllWhenNoLeague() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    _ = try await feed.otherLive()
    let q = query(try XCTUnwrap(MockURLProtocol.requests.first))
    XCTAssertEqual(q["live"], "all")
    XCTAssertNil(q["league"])
  }

  // MARK: - Matchsight: Premier League + Champions League

  private func fixtureJSON(id: Int, kickoff: String, league: Int, round: String,
                           home: (Int, String), away: (Int, String)) -> String {
    """
    {"fixture":{"id":\(id),"date":"\(kickoff)","timestamp":null,"venue":null,"status":{"short":"NS","elapsed":null}},
     "league":{"id":\(league),"name":"L\(league)","country":"World","season":2026,"round":"\(round)"},
     "teams":{"home":{"id":\(home.0),"name":"\(home.1)","logo":"https://media.api-sports.io/football/teams/\(home.0).png"},
              "away":{"id":\(away.0),"name":"\(away.1)","logo":"https://media.api-sports.io/football/teams/\(away.0).png"}},
     "goals":{"home":null,"away":null}}
    """
  }

  private func envelope(_ items: [String]) -> Data {
    Data("{\"errors\":[],\"results\":\(items.count),\"response\":[\(items.joined(separator: ","))]}".utf8)
  }

  private func teamJSON(_ id: Int, _ name: String, _ code: String) -> String {
    "{\"team\":{\"id\":\(id),\"name\":\"\(name)\",\"code\":\"\(code)\",\"logo\":\"https://media.api-sports.io/football/teams/\(id).png\"}}"
  }

  // MARK: - upcoming fixtures (Coming up)

  private func installUpcomingRouter() {
    MockURLProtocol.handler = { [self] request in
      let q = query(request)
      let shared = fixtureJSON(id: 3, kickoff: "2026-11-08T16:30:00+00:00", league: 39, round: "R11",
                               home: (42, "Arsenal"), away: (49, "Chelsea"))
      let items: [String]
      switch q["team"] {
      case "42":
        items = [fixtureJSON(id: 1, kickoff: "2026-11-01T15:00:00+00:00", league: 39, round: "R10",
                             home: (42, "Arsenal"), away: (40, "Liverpool")), shared]
      case "49":
        items = [shared, fixtureJSON(id: 2, kickoff: "2026-11-04T20:00:00+00:00", league: 2, round: "MD4",
                                     home: (49, "Chelsea"), away: (541, "Real Madrid"))]
      default:
        items = []
      }
      return ok(request.url, envelope(items))
    }
  }

  func testUpcomingFixturesAskEachTeamForItsNextTenAndMerge() async throws {
    installUpcomingRouter()
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026, session: makeSession())
    let fixtures = try await feed.upcomingFixtures(teamIds: [42, 49])
    XCTAssertEqual(fixtures.map(\.id), [1, 2, 3], "merged, one copy of the shared match, by kickoff")
    XCTAssertEqual(MockURLProtocol.requests.count, 2)
    for req in MockURLProtocol.requests {
      XCTAssertEqual(req.url?.path, "/fixtures")
      XCTAssertEqual(query(req)["next"], "10")
      XCTAssertNil(query(req)["date"])
      XCTAssertNil(query(req)["league"], "next=N is per team, across competitions")
    }
    XCTAssertEqual(Set(MockURLProtocol.requests.compactMap { query($0)["team"] }), ["42", "49"])
  }

  func testUpcomingFixturesAreFetchedAtMostEverySixHours() async throws {
    installUpcomingRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(), now: { clock.date })
    _ = try await feed.upcomingFixtures(teamIds: [42, 49])
    clock.date += 5 * 3600
    _ = try await feed.upcomingFixtures(teamIds: [49, 42])
    XCTAssertEqual(MockURLProtocol.requests.count, 2, "same teams within 6 h: served from cache")
    _ = try await feed.upcomingFixtures(teamIds: [42])
    XCTAssertEqual(MockURLProtocol.requests.count, 3, "a different team set refetches")
    clock.date += 6 * 3600
    _ = try await feed.upcomingFixtures(teamIds: [42])
    XCTAssertEqual(MockURLProtocol.requests.count, 4)
  }

  func testUpcomingFixturesWithNoTeamsMakesNoRequest() async throws {
    installUpcomingRouter()
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    let fixtures = try await feed.upcomingFixtures(teamIds: [])
    XCTAssertTrue(fixtures.isEmpty)
    XCTAssertTrue(MockURLProtocol.requests.isEmpty)
  }

  func testTodaysFixturesQueriesEachLeagueAndMerges() async throws {
    MockURLProtocol.handler = { [self] request in
      let q = query(request)
      XCTAssertEqual(q["season"], "2026")
      if q["league"] == "39" {
        return ok(request.url, envelope([fixtureJSON(id: 11, kickoff: "2026-10-31T17:30:00+00:00", league: 39,
                                                     round: "Regular Season - 10", home: (42, "Arsenal"), away: (49, "Chelsea"))]))
      }
      return ok(request.url, envelope([fixtureJSON(id: 22, kickoff: "2026-10-31T12:30:00+00:00", league: 2,
                                                   round: "League Stage - 4", home: (85, "Paris Saint Germain"), away: (40, "Liverpool"))]))
    }
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026, session: makeSession())
    let fixtures = try await feed.todaysFixtures()
    XCTAssertEqual(fixtures.map(\.id), [22, 11], "both leagues, sorted by kickoff")
    XCTAssertEqual(Set(MockURLProtocol.requests.compactMap { query($0)["league"] }), ["39", "2"])
  }

  func testOtherLiveUsesDashJoinedLeagues() async throws {
    installDefaultRouter()
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026, session: makeSession())
    _ = try await feed.otherLive()
    XCTAssertEqual(query(try XCTUnwrap(MockURLProtocol.requests.first))["live"], "39-2")
  }

  func testPremierLeagueClubsHaveCodeAndLogo() async throws {
    MockURLProtocol.handler = { [self] request in
      XCTAssertEqual(request.url?.path, "/teams")
      XCTAssertEqual(query(request)["league"], "39")
      XCTAssertEqual(query(request)["season"], "2026")
      return ok(request.url, envelope([teamJSON(49, "Chelsea", "CHE"), teamJSON(42, "Arsenal", "ARS")]))
    }
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026, session: makeSession())
    let clubs = try await feed.clubs(leagueId: ApiFootballFeed.premierLeague)
    XCTAssertEqual(clubs.map(\.name), ["Arsenal", "Chelsea"], "sorted by name")
    XCTAssertEqual(clubs.first?.code, "ARS")
    XCTAssertEqual(clubs.first?.logoURL?.absoluteString, "https://media.api-sports.io/football/teams/42.png")
  }

  func testChampionsLeagueClubsAreLeaguePhaseOnly() async throws {
    MockURLProtocol.handler = { [self] request in
      if request.url?.path == "/teams" {
        return ok(request.url, envelope([teamJSON(42, "Arsenal", "ARS"), teamJSON(85, "Paris Saint Germain", "PSG"),
                                         teamJSON(999, "Qualifier FC", "QUA")]))
      }
      XCTAssertEqual(query(request)["round"], "League Stage - 1")
      return ok(request.url, envelope([fixtureJSON(id: 1, kickoff: "2026-09-16T19:00:00+00:00", league: 2,
                                                   round: "League Stage - 1", home: (85, "Paris Saint Germain"), away: (42, "Arsenal"))]))
    }
    let feed = ApiFootballFeed(apiKey: "K", leagueIds: [39, 2], season: 2026, session: makeSession())
    let clubs = try await feed.clubs(leagueId: ApiFootballFeed.championsLeague)
    XCTAssertEqual(clubs.map(\.id), [42, 85])
    XCTAssertEqual(clubs.map(\.code), ["ARS", "PSG"])
  }

  // MARK: - possession cache budget

  private func statisticsRequestCount() -> Int {
    MockURLProtocol.requests.filter { $0.url?.path == "/fixtures/statistics" }.count
  }

  func testPossessionCachedWithin60Seconds() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1000))
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(), now: { clock.date })

    _ = try await feed.liveSnapshot(fixtureId: 1001)   // t=1000 → fetch stats
    clock.date = Date(timeIntervalSince1970: 1010)      // +10s
    let second = try await feed.liveSnapshot(fixtureId: 1001)

    XCTAssertEqual(statisticsRequestCount(), 1, "10s apart should reuse cached possession")
    XCTAssertEqual(second.possessionHome, 65)           // served from cache
  }

  func testPossessionRefetchedAfter60Seconds() async throws {
    installDefaultRouter()
    let clock = Clock(Date(timeIntervalSince1970: 1000))
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(), now: { clock.date })

    _ = try await feed.liveSnapshot(fixtureId: 1001)   // t=1000
    clock.date = Date(timeIntervalSince1970: 1070)      // +70s
    _ = try await feed.liveSnapshot(fixtureId: 1001)

    XCTAssertEqual(statisticsRequestCount(), 2, "70s apart should re-fetch possession")
  }

  func testPossessionFailureLeavesSnapshotIntact() async throws {
    // Fixture succeeds; statistics fails — snapshot must still return, possession nil.
    MockURLProtocol.handler = { [self] request in
      let url = request.url!
      if url.path.hasSuffix("/fixtures/statistics") {
        throw URLError(.timedOut)
      }
      return ok(url, try resourceData("apifootball-live"))
    }
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession(),
                               now: { Date(timeIntervalSince1970: 0) })
    let snap = try await feed.liveSnapshot(fixtureId: 1001)
    XCTAssertEqual(snap.score, ScoreLine(home: 2, away: 1))
    XCTAssertNil(snap.possessionHome)
  }

  // MARK: - error surfacing

  func test200WithErrorObjectThrowsUnauthorized() async throws {
    let body = Data(#"{"get":"fixtures","errors":{"token":"Missing application key"},"results":0,"response":[]}"#.utf8)
    MockURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
    }
    let feed = ApiFootballFeed(apiKey: "BAD", session: makeSession())
    await assertThrowsFeedError(.unauthorized) { try await feed.todaysFixtures() }
  }

  func test200WithQuotaErrorThrowsQuotaExceeded() async throws {
    let body = Data(#"{"get":"fixtures","errors":{"requests":"You have reached the request limit for the day"},"results":0,"response":[]}"#.utf8)
    MockURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
    }
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    await assertThrowsFeedError(.quotaExceeded) { try await feed.todaysFixtures() }
  }

  func test429StatusThrowsQuotaExceeded() async throws {
    MockURLProtocol.handler = { request in
      (HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
    }
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    await assertThrowsFeedError(.quotaExceeded) { try await feed.todaysFixtures() }
  }

  func testNetworkFailureThrowsNetworkError() async throws {
    MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    let feed = ApiFootballFeed(apiKey: "K", session: makeSession())
    do {
      _ = try await feed.todaysFixtures()
      XCTFail("expected network error")
    } catch let error as FeedError {
      guard case .network = error else {
        return XCTFail("expected .network, got \(error)")
      }
    }
  }

  // MARK: - assertion helper

  private func assertThrowsFeedError(_ expected: FeedError,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     _ body: () async throws -> Void) async {
    do {
      try await body()
      XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as FeedError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("expected FeedError.\(expected), got \(error)", file: file, line: line)
    }
  }
}
