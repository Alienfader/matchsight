import XCTest
@testable import CopaHUDCore

/// LIVE smoke test against Meta Model API (muse-spark-1.3) — the Phase 1
/// proof that real model output survives InsightValidator. Skipped unless
/// META_MODEL_API_KEY is set in the shell; the key is never printed.
///
///   META_MODEL_API_KEY=… swift test --filter MetaModelLiveTests
final class MetaModelLiveTests: XCTestCase {
  private let brazil = Team(id: 6, name: "Brazil")
  private let morocco = Team(id: 31, name: "Morocco")

  private func context() -> MatchInsightContext {
    let snap = MatchSnapshot(fixtureId: 1489371, home: brazil, away: morocco,
                             score: ScoreLine(home: 2, away: 1), status: .secondHalf,
                             elapsedMinutes: 67, possessionHome: nil,
                             groupLabel: "Group Stage - 1", kickoff: Date(timeIntervalSince1970: 0))
    func event(_ minute: Int, _ team: Team, _ player: String, _ assist: String?,
               _ kind: MatchEvent.Kind) -> MatchEvent {
      MatchEvent(id: "\(minute)-\(player)", fixtureId: 1489371, minute: minute, extraMinute: nil,
                 team: team, player: player, assist: assist, kind: kind)
    }
    let events = [
      event(18, brazil, "Raphinha", "Vinícius Júnior", .goal(.normal)),
      event(28, morocco, "Brahim Díaz", "Hakimi", .goal(.normal)),
      event(36, brazil, "Casemiro", nil, .card(.yellow)),
      event(55, brazil, "Endrick", "Bruno Guimarães", .goal(.normal)),
      event(61, brazil, "Endrick", "Rodrygo", .substitution),  // Endrick off, Rodrygo on
    ]
    let lineups = [
      Lineup(fixtureId: 1489371, team: brazil, formation: "4-3-3", startXI: [], coach: "Dorival Júnior"),
      Lineup(fixtureId: 1489371, team: morocco, formation: "4-1-4-1", startXI: [], coach: "Walid Regragui"),
    ]
    let stats = MatchStats(
      home: TeamStats(totalShots: 11, shotsOnGoal: 5, expectedGoals: "1.62"),
      away: TeamStats(totalShots: 6, shotsOnGoal: 2, expectedGoals: "0.71"))
    return MatchInsightContext.build(snapshot: snap, events: events, lineups: lineups,
                                     stats: stats, isScripted: false)
  }

  func testLiveInsightsPassValidation() async throws {
    let key = ProcessInfo.processInfo.environment["META_MODEL_API_KEY"] ?? ""
    try XCTSkipIf(key.isEmpty, "META_MODEL_API_KEY not set — live test skipped")

    var config = MetaModelConfig()
    config.apiKey = key
    config.timeout = 20
    let service = MetaModelInsightService(config: config)
    let c = context()
    print("LIVE model=\(config.model) facts=\(c.facts.count)")

    for question in InsightQuestion.presets + [.spoken("Who has covered the most distance today?")] {
      let start = Date()
      do {
        let insight = try await service.insight(for: c, question: question)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("LIVE \(question.label) | \(insight.basis.rawValue) | \(insight.factIds) | \(insight.title) | \(insight.body) | \(ms) ms")
        XCTAssertEqual(insight.source, .model)
      } catch {
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("LIVE \(question.label) | FAILED \(error) | \(ms) ms")
        XCTFail("\(question.label): \(error)")
      }
    }
  }

  /// LIVE: Muse Voice Transcribe on a synthetic 2s question (macOS `say`),
  /// biased with the match's player names.
  func testLiveTranscription() async throws {
    let key = ProcessInfo.processInfo.environment["META_MODEL_API_KEY"] ?? ""
    try XCTSkipIf(key.isEmpty, "META_MODEL_API_KEY not set — live test skipped")
    let url = try XCTUnwrap(Bundle.module.url(forResource: "voice-question", withExtension: "wav"))
    var config = MetaModelConfig()
    config.apiKey = key
    config.timeout = 20
    let start = Date()
    do {
      let text = try await MetaVoiceTranscriber(config: config)
        .transcribe(wav: try Data(contentsOf: url), keywords: ["Paquetá", "Rodrygo", "Brazil"])
      print("LIVE transcribe | \(text) | \(Int(Date().timeIntervalSince(start) * 1000)) ms")
      XCTAssertTrue(text.lowercased().contains("brazil"), text)
    } catch {
      print("LIVE transcribe | FAILED \(error) | \(Int(Date().timeIntervalSince(start) * 1000)) ms")
      throw error
    }
  }
}
