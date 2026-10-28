import XCTest
@testable import CopaHUDCore

/// InsightValidator is the grounding gate between the model and the glasses:
/// length limits, basis rules, and "cite only facts we actually sent".
/// InsightTemplate is the data-only fallback whenever the gate says no.
final class MatchInsightTests: XCTestCase {
  private let brazil = Team(id: 6, name: "Brazil")
  private let morocco = Team(id: 31, name: "Morocco")

  private func context() -> MatchInsightContext {
    let snap = MatchSnapshot(fixtureId: 1, home: brazil, away: morocco,
                             score: ScoreLine(home: 2, away: 1), status: .secondHalf,
                             elapsedMinutes: 67, possessionHome: nil,
                             groupLabel: nil, kickoff: Date(timeIntervalSince1970: 0))
    let goal = MatchEvent(id: "g", fixtureId: 1, minute: 18, extraMinute: nil, team: brazil,
                          player: "Raphinha", assist: nil, kind: .goal(.normal))
    let stats = MatchStats(home: TeamStats(totalShots: 9), away: TeamStats(totalShots: 4))
    return MatchInsightContext.build(snapshot: snap, events: [goal], lineups: [],
                                     stats: stats, isScripted: false)
  }

  private func raw(title: String = "BRAZIL IN FRONT",
                   body: String = "Brazil lead 2–1 and have outshot Morocco 9 to 4.",
                   basis: InsightBasis = .dataInference,
                   factIds: [String] = ["F1"]) -> RawInsight {
    RawInsight(title: title, body: body, basis: basis, factIds: factIds)
  }

  private func assertRejects(_ r: RawInsight, _ expected: InsightValidationError,
                             file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try InsightValidator.validate(r, context: context(), source: .model),
                         file: file, line: line) { error in
      XCTAssertEqual(error as? InsightValidationError, expected, file: file, line: line)
    }
  }

  func testValidInsightPasses() throws {
    let c = context()
    let insight = try InsightValidator.validate(raw(), context: c, source: .model)
    XCTAssertEqual(insight.source, .model)
    XCTAssertEqual(insight.fingerprint, c.fingerprint)
    XCTAssertEqual(insight.factIds, ["F1"])
  }

  func testWhitespaceIsCollapsed() throws {
    let insight = try InsightValidator.validate(
      raw(body: "Brazil lead.\n\n  Morocco chase."), context: context(), source: .model)
    XCTAssertEqual(insight.body, "Brazil lead. Morocco chase.")
  }

  func testBodyOver150Rejected() {
    assertRejects(raw(body: String(repeating: "a", count: 151)), .bodyTooLong(151))
  }

  func testEmptyRejected() {
    assertRejects(raw(title: "   "), .empty)
  }

  func testLongTitleTruncatedOnWordBoundary() throws {
    let insight = try InsightValidator.validate(
      raw(title: "WHY BRAZIL CONTROL THE MIDFIELD BATTLE"), context: context(), source: .model)
    XCTAssertEqual(insight.title, "WHY BRAZIL CONTROL THE…")
    XCTAssertLessThanOrEqual(insight.title.count, MatchInsight.maxTitle)
  }

  func testUnknownFactRejected() {
    assertRejects(raw(factIds: ["F99"]), .unknownFact("F99"))
  }

  func testObservedRequiresFacts() throws {
    assertRejects(raw(basis: .observed, factIds: []), .missingFacts)
    XCTAssertNoThrow(try InsightValidator.validate(raw(basis: .generalTactics, factIds: []),
                                                   context: context(), source: .model))
  }

  func testVisionClaimRejectedForAllBases() {
    let body = "Brazil's pressing is forcing Morocco into long balls."
    assertRejects(raw(body: body), .ungroundedClaim("pressing"))
    assertRejects(raw(body: body, basis: .generalTactics, factIds: []), .ungroundedClaim("pressing"))
  }

  func testVisionTermsMatchWholeWords() throws {
    XCTAssertNoThrow(try InsightValidator.validate(
      raw(body: "Brazil have impressed with 9 shots."), context: context(), source: .model))
    assertRejects(raw(body: "Brazil's high press forced the errors."), .ungroundedClaim("press"))
  }

  func testTemplateUsesOnlyContextFacts() {
    let c = context()
    let t = InsightTemplate.make(context: c)
    XCTAssertEqual(t.source, .template)
    XCTAssertTrue(Set(t.factIds).isSubset(of: c.factIDs()))
    XCTAssertLessThanOrEqual(t.body.count, MatchInsight.maxBody)
    XCTAssertTrue(t.body.contains("Score: Brazil 2–1 Morocco"))
    XCTAssertTrue(t.body.contains("18' GOAL Brazil: Raphinha"))
  }

  func testTemplateWithNoFacts() {
    let empty = MatchInsightContext(fixtureId: 1, headline: "", facts: [], isScripted: false)
    let t = InsightTemplate.make(context: empty)
    XCTAssertEqual(t.title, "AI INSIGHT")
    XCTAssertEqual(t.body, "Waiting for match data.")
    XCTAssertEqual(t.factIds, [])
  }

  // Spoken questions are free-form, so "general tactics" must not become an
  // uncited channel for invented facts ("How old is Rodrygo?" → made-up age).
  func testSpokenAnswersMustCiteFacts() {
    let uncited = raw(body: "Rodrygo is 25 and loves big games.", basis: .generalTactics, factIds: [])
    XCTAssertThrowsError(try InsightValidator.validate(uncited, context: context(), source: .model,
                                                       requireCitations: true)) { error in
      XCTAssertEqual(error as? InsightValidationError, .missingFacts)
    }
    XCTAssertNoThrow(try InsightValidator.validate(raw(basis: .generalTactics, factIds: ["F1"]),
                                                   context: context(), source: .model,
                                                   requireCitations: true))
  }

  // Spoken questions may get a general-knowledge answer (a club's city, a
  // stadium) that no match fact covers. It is labelled as such on the glasses
  // and is never allowed for the automatic insights.
  func testSpokenGeneralKnowledgeNeedsNoCitation() throws {
    let answer = raw(title: "CHELSEA", body: "Chelsea are a London club; they play at Stamford Bridge.",
                     basis: .generalKnowledge, factIds: [])
    let insight = try InsightValidator.validate(answer, context: context(), source: .model,
                                                requireCitations: true, allowGeneralKnowledge: true)
    XCTAssertEqual(insight.basis, .generalKnowledge)
  }

  func testGeneralKnowledgeRejectedOutsideSpokenQuestions() {
    assertRejects(raw(body: "Chelsea are a London club.", basis: .generalKnowledge, factIds: []),
                  .generalKnowledgeNotAllowed)
  }

  func testGeneralKnowledgeStillPassesTheOtherChecks() {
    func check(_ r: RawInsight, _ expected: InsightValidationError) {
      XCTAssertThrowsError(try InsightValidator.validate(r, context: context(), source: .model,
                                                         requireCitations: true,
                                                         allowGeneralKnowledge: true)) { error in
        XCTAssertEqual(error as? InsightValidationError, expected)
      }
    }
    check(raw(body: "Chelsea are known for pressing high.", basis: .generalKnowledge, factIds: []),
          .ungroundedClaim("pressing"))
    check(raw(body: "Chelsea are a London club.", basis: .generalKnowledge, factIds: ["F99"]),
          .unknownFact("F99"))
    check(raw(body: String(repeating: "x", count: 151), basis: .generalKnowledge, factIds: []),
          .bodyTooLong(151))
  }
}

