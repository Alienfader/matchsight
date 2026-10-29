import XCTest
@testable import CopaHUDCore

/// The heart of the app. Every property here is law from BRIEF-STRIKER.md:
/// dedup by stable id, VAR reversal (vanish / explicit / collapse), multi-goal
/// burst score reconstruction, HT/FT once, other-match goals, mid-match seeding.
final class MatchEngineTests: XCTestCase {
  // MARK: - Fixtures & builders

  let bra = Team(id: 6, name: "Brazil")
  let arg = Team(id: 26, name: "Argentina")

  private func snap(_ status: MatchStatus, _ h: Int, _ a: Int,
                    min: Int? = nil, fixture: Int = 1,
                    home: Team? = nil, away: Team? = nil,
                    poss: Int? = nil) -> MatchSnapshot {
    MatchSnapshot(fixtureId: fixture, home: home ?? bra, away: away ?? arg,
                  score: ScoreLine(home: h, away: a), status: status,
                  elapsedMinutes: min, possessionHome: poss, groupLabel: nil,
                  kickoff: Date(timeIntervalSince1970: 0))
  }

  /// Builds an event with a stable, content-derived id — re-creating the same
  /// event yields the same id, exactly like the feed's synthesized ids.
  private func ev(_ kind: MatchEvent.Kind, _ team: Team, min: Int,
                  extra: Int? = nil, player: String? = nil,
                  assist: String? = nil, fixture: Int = 1) -> MatchEvent {
    let tag: String
    switch kind {
    case .goal(let d): tag = "goal-\(d.rawValue)"
    case .card(let d): tag = "card-\(d.rawValue)"
    case .substitution: tag = "sub"
    case .varDecision(let detail): tag = "var-\(detail)"
    case .unknown(let t, let d): tag = "unk-\(t)-\(d)"
    }
    let id = "\(fixture)-\(min)+\(extra ?? 0)-\(team.id)-\(tag)-\(player ?? "")"
    return MatchEvent(id: id, fixtureId: fixture, minute: min, extraMinute: extra,
                      team: team, player: player, assist: assist, kind: kind)
  }

  private func goal(_ d: MatchEvent.GoalDetail, _ team: Team, min: Int,
                    extra: Int? = nil, player: String? = nil,
                    assist: String? = nil, fixture: Int = 1) -> MatchEvent {
    ev(.goal(d), team, min: min, extra: extra, player: player, assist: assist, fixture: fixture)
  }

  // MARK: - Goal

  func testGoalEmitsGoalMomentWithScorerAssistAndScore() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 67, player: "Neymar", assist: "Vinícius Júnior")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 67), events: [g])

    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 0))
    XCTAssertEqual(out[0].minute, 67)
    XCTAssertEqual(out[0].kind, .goal(scorer: "Neymar", assist: "Vinícius Júnior", detail: .normal))
  }

  func testAwayGoalCountsForAwaySide() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, arg, min: 20, player: "Messi")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 1, min: 20), events: [g])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].score, ScoreLine(home: 0, away: 1))
  }

  // MARK: - Dedup

  func testDedupAcrossRePolls() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 12, player: "Raphinha")

    let first = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 12), events: [g])
    XCTAssertEqual(first.count, 1)

    // Re-poll the IDENTICAL event list twice — nothing new emits.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 13), events: [g]), [])
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 14), events: [g]), [])
  }

  // MARK: - VAR reversal

  func testVarReversalByVanish() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 30, player: "Endrick")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 30), events: [g]).count, 1)

    // Goal vanishes from the feed AND the snapshot score drops back to 0-0.
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 33), events: [])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .varDecision(.goalOverturned))
    XCTAssertEqual(out[0].score, ScoreLine(home: 0, away: 0))

    // Bookkeeping cleared: the same goal id can never re-fire afterwards.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 34), events: []), [])
  }

  func testVarReversalByExplicitEvent() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    // A standalone VAR "Goal Disallowed" event (no counted goal vanishing).
    let v = ev(.varDecision(detail: "Goal Disallowed"), bra, min: 41)
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 41), events: [v])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .varDecision(.goalOverturned))
  }

  func testVarReversalVanishAndExplicitEventCollapseToOne() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 50, player: "Vini")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 50), events: [g]).count, 1)

    // Same poll: goal vanishes AND an explicit "Goal cancelled" VAR event lands.
    let v = ev(.varDecision(detail: "Goal cancelled"), bra, min: 52)
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 52), events: [v])
    XCTAssertEqual(out.count, 1, "vanish + explicit VAR event must collapse to ONE moment")
    XCTAssertEqual(out[0].kind, .varDecision(.goalOverturned))
    XCTAssertEqual(out[0].score, ScoreLine(home: 0, away: 0))
  }

  // MARK: - Multi-goal burst

  func testMultiGoalBurstReconstructsIntermediateScoresInOrder() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    // Two goals in one poll, out of chronological order in the array.
    let away = goal(.normal, arg, min: 40, player: "Messi")
    let home = goal(.normal, bra, min: 22, player: "Rodrygo")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 1, min: 40),
                                    events: [away, home])

    XCTAssertEqual(out.count, 2)
    // Chronological order: 22' home first (1-0), then 40' away (1-1).
    XCTAssertEqual(out[0].minute, 22)
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 0))
    XCTAssertEqual(out[1].minute, 40)
    XCTAssertEqual(out[1].score, ScoreLine(home: 1, away: 1))
  }

  func testLastGoalTrustsSnapshotOnFeedLag() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    // Feed sends only TWO goal events but the snapshot already reads 3-0 (lag).
    let g1 = goal(.normal, bra, min: 10, player: "A")
    let g2 = goal(.normal, bra, min: 20, player: "B")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 3, 0, min: 21),
                                    events: [g1, g2])
    XCTAssertEqual(out.count, 2)
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 0))
    // Last goal moment is corrected up to the authoritative snapshot score.
    XCTAssertEqual(out[1].score, ScoreLine(home: 3, away: 0))
  }

  // MARK: - Score before the event (API-Football often updates the score first)

  func testScoreRiseWithoutAnEventCelebratesAtOnce() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 1, min: 44), events: [])
    XCTAssertEqual(out, [MatchMoment(fixtureId: 1, kind: .goal(scorer: nil, assist: nil, detail: .normal),
                                     score: ScoreLine(home: 0, away: 1), minute: 44)])
  }

  func testTheLateEventOfAnAnnouncedGoalDoesNotCelebrateAgain() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 1, min: 44), events: [])
    let g = goal(.normal, arg, min: 44, player: "Messi")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 1, min: 45), events: [g]), [])
    // The next real goal still celebrates, with its scorer.
    let g2 = goal(.normal, bra, min: 50, player: "Neymar")
    let out = engine.ingestFollowed(snapshot: snap(.secondHalf, 1, 1, min: 50), events: [g, g2])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .goal(scorer: "Neymar", assist: nil, detail: .normal))
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 1))
  }

  // MARK: - Event before the score (seen on hardware 2026-10-28, Bahia 6')

  func testAGoalEventAheadOfTheScoreCelebratesOnceWithItsScore() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 6, player: "Rodrigo Nestor")
    let first = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 6), events: [g])
    XCTAssertEqual(first, [MatchMoment(fixtureId: 1,
                                       kind: .goal(scorer: "Rodrigo Nestor", assist: nil, detail: .normal),
                                       score: ScoreLine(home: 1, away: 0), minute: 6)])
    // The score catches up: nothing new to announce.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 6), events: [g]), [])
    // The next goal still celebrates once, with the right score.
    let g2 = goal(.normal, bra, min: 10, player: "B")
    let next = engine.ingestFollowed(snapshot: snap(.firstHalf, 2, 0, min: 10), events: [g, g2])
    XCTAssertEqual(next.map(\.score), [ScoreLine(home: 2, away: 0)])
  }

  func testTheScoreCatchingUpPlusAnotherGoalAnnouncesOnlyTheNewOne() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 6, player: "A")
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 6), events: [g])
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 2, 0, min: 9), events: [g])
    XCTAssertEqual(out, [MatchMoment(fixtureId: 1, kind: .goal(scorer: nil, assist: nil, detail: .normal),
                                     score: ScoreLine(home: 2, away: 0), minute: 9)])
  }

  func testAGoalEventThatVanishesBeforeTheScoreShowedItIsOverturned() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g = goal(.normal, bra, min: 6, player: "A")
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 6), events: [g])
    let gone = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 8), events: [])
    XCTAssertEqual(gone, [MatchMoment(fixtureId: 1, kind: .varDecision(.goalOverturned),
                                      score: ScoreLine(home: 0, away: 0), minute: 6)])
    // A later real goal is not swallowed.
    let g2 = goal(.normal, bra, min: 20, player: "B")
    let next = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 20), events: [g2])
    XCTAssertEqual(next.map(\.score), [ScoreLine(home: 1, away: 0)])
  }

  func testTwoGoalsWithoutEventsCelebrateTwiceInOrder() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 1, min: 30), events: [])
    XCTAssertEqual(out.map(\.score), [ScoreLine(home: 1, away: 0), ScoreLine(home: 1, away: 1)])
  }

  func testFollowingMidMatchBeforeAnyEventsStaysSilent() {
    var engine = MatchEngine()
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 20), events: []), [])
    // Its event arriving later is history, not a new goal.
    let g = goal(.normal, bra, min: 12, player: "A")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 21), events: [g]), [])
  }

  func testAnAnnouncedGoalThatDisappearsIsOverturned() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 30), events: [])
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 32), events: [])
    XCTAssertEqual(out.map(\.kind), [.varDecision(.goalOverturned)])
    XCTAssertEqual(out.first?.score, ScoreLine(home: 0, away: 0))
  }

  func testTheMissingEventAfterFeedLagDoesNotCelebrateAgain() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: [])
    let g1 = goal(.normal, bra, min: 10, player: "A")
    let g2 = goal(.normal, bra, min: 20, player: "B")
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 3, 0, min: 21), events: [g1, g2])
    let g3 = goal(.normal, bra, min: 21, player: "C")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 3, 0, min: 22), events: [g1, g2, g3]), [])
  }

  // MARK: - HT / FT transitions

  func testHalfTimeFiresExactlyOnce() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 1), events: [])
    let out = engine.ingestFollowed(snapshot: snap(.halfTime, 0, 0, min: 45), events: [])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .halfTime)

    // Re-polling half-time does not re-fire.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.halfTime, 0, 0, min: 45), events: []), [])
    // Second half resumes with no spurious moment.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.secondHalf, 0, 0, min: 46), events: []), [])
  }

  func testFullTimeFiresExactlyOnce() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.secondHalf, 2, 1, min: 89), events: [])
    let out = engine.ingestFollowed(snapshot: snap(.finished, 2, 1, min: 90), events: [])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .fullTime)
    XCTAssertEqual(out[0].score, ScoreLine(home: 2, away: 1))

    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.finished, 2, 1, min: 90), events: []), [])
  }

  // MARK: - Other matches

  func testOtherMatchGoalOnScoreIncrease() {
    var engine = MatchEngine()
    XCTAssertEqual(engine.ingestOthers([snap(.firstHalf, 0, 0, fixture: 99)]), [])  // first sighting
    let out = engine.ingestOthers([snap(.secondHalf, 1, 0, min: 70, fixture: 99)])
    XCTAssertEqual(out.count, 1)
    if case .otherMatchGoal(let s, let scorer) = out[0].kind {
      XCTAssertEqual(s.fixtureId, 99)
      XCTAssertNil(scorer)
    } else {
      XCTFail("expected otherMatchGoal")
    }
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 0))
    XCTAssertEqual(out[0].minute, 70)
  }

  func testOtherMatchDoubleJumpEmitsTwoMoments() {
    var engine = MatchEngine()
    _ = engine.ingestOthers([snap(.secondHalf, 2, 0, fixture: 99)])
    let out = engine.ingestOthers([snap(.secondHalf, 2, 2, min: 80, fixture: 99)])
    XCTAssertEqual(out.count, 2, "2→4 total goals = two moments")
  }

  func testOtherMatchDecreaseIsSilent() {
    var engine = MatchEngine()
    _ = engine.ingestOthers([snap(.secondHalf, 2, 1, fixture: 99)])
    // VAR elsewhere drops the score — update silently, no moment.
    XCTAssertEqual(engine.ingestOthers([snap(.secondHalf, 1, 1, fixture: 99)]), [])
    // And the new baseline is respected: 1→2 is a single goal again.
    XCTAssertEqual(engine.ingestOthers([snap(.secondHalf, 2, 1, fixture: 99)]).count, 1)
  }

  func testOtherMatchFirstSightingIsSilent() {
    var engine = MatchEngine()
    XCTAssertEqual(engine.ingestOthers([snap(.secondHalf, 3, 1, fixture: 99)]), [])
  }

  // MARK: - First-ingest seeding

  func testMidMatchFirstIngestSeedsSilently() {
    var engine = MatchEngine()
    // User follows mid-match: live with history already present.
    let history = [goal(.normal, bra, min: 12, player: "A"),
                   goal(.normal, arg, min: 30, player: "B")]
    let seeded = engine.ingestFollowed(snapshot: snap(.secondHalf, 1, 1, min: 55),
                                       events: history)
    XCTAssertEqual(seeded, [], "history must not replay as takeovers")

    // Re-polling the same history still nothing.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.secondHalf, 1, 1, min: 56),
                                         events: history), [])

    // A genuinely NEW goal after seeding fires normally.
    let fresh = goal(.normal, bra, min: 60, player: "C")
    let out = engine.ingestFollowed(snapshot: snap(.secondHalf, 2, 1, min: 60),
                                    events: history + [fresh])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].score, ScoreLine(home: 2, away: 1))
  }

  func testPreKickoffFirstIngestFiresNormally() {
    var engine = MatchEngine()
    // First ingest before kickoff (notStarted) — NOT mid-match, so nothing seeds.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.notStarted, 0, 0), events: []), [])
    let g = goal(.normal, bra, min: 5, player: "A")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 5), events: [g])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .goal(scorer: "A", assist: nil, detail: .normal))
  }

  func testMidMatchSeedingStillFiresStatusTransitions() {
    var engine = MatchEngine()
    let history = [goal(.normal, bra, min: 12, player: "A")]
    _ = engine.ingestFollowed(snapshot: snap(.secondHalf, 1, 0, min: 55), events: history)
    // FT transition after seeding must still fire.
    let out = engine.ingestFollowed(snapshot: snap(.finished, 1, 0, min: 90), events: history)
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .fullTime)
  }

  // MARK: - VAR detail mapping & special goal/card kinds

  func testPenaltyAwardedViaVarDetail() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0), events: [])
    let v = ev(.varDecision(detail: "Penalty confirmed"), bra, min: 33)
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 33), events: [v])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .penaltyAwarded(team: bra))
  }

  func testVarGoalConfirmedAndAwardedAndPenaltyCancelled() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0), events: [])
    let stands = ev(.varDecision(detail: "Goal confirmed"), bra, min: 10)
    let awarded = ev(.varDecision(detail: "Goal awarded"), bra, min: 11)
    let penCancel = ev(.varDecision(detail: "Penalty cancelled"), arg, min: 12)
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 12),
                                    events: [stands, awarded, penCancel])
    XCTAssertEqual(out.map(\.kind), [
      .varDecision(.goalStands),
      .varDecision(.goalAwarded),
      .varDecision(.penaltyCancelled),
    ])
  }

  func testUnknownVarDetailMapsToOther() {
    XCTAssertEqual(VarOutcome(detail: "Card upgrade"), .other("Card upgrade"))
  }

  func testMissedPenaltyEmitsNoMoment() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0), events: [])
    let miss = goal(.missedPenalty, bra, min: 25, player: "A")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 25), events: [miss]), [])
    // And it is recorded as seen — re-poll stays silent.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0, min: 26), events: [miss]), [])
  }

  func testOwnGoalCountsForOpponentAndCarriesDetail() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0), events: [])
    // Argentina player scores an own goal → Brazil's tally goes up.
    let og = goal(.ownGoal, arg, min: 18, player: "Otamendi")
    let out = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 18), events: [og])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].score, ScoreLine(home: 1, away: 0))
    XCTAssertEqual(out[0].kind, .goal(scorer: "Otamendi", assist: nil, detail: .ownGoal))
  }

  func testRedCardEmitsMomentYellowDoesNot() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0), events: [])
    let yellow = ev(.card(.yellow), arg, min: 20, player: "Booked")
    let red = ev(.card(.red), arg, min: 70, player: "Otamendi")
    let out = engine.ingestFollowed(snapshot: snap(.secondHalf, 0, 0, min: 70),
                                    events: [yellow, red])
    XCTAssertEqual(out.count, 1)
    XCTAssertEqual(out[0].kind, .redCard(player: "Otamendi", team: arg))
    XCTAssertEqual(out[0].minute, 70)
  }

  func testSubstitutionEmitsNoMoment() {
    var engine = MatchEngine()
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 0, 0), events: [])
    let sub = ev(.substitution, bra, min: 60, player: "On")
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.secondHalf, 0, 0, min: 60), events: [sub]), [])
  }

  // MARK: - reset

  func testResetDropsAllFixtureState() {
    var engine = MatchEngine()
    let g = goal(.normal, bra, min: 12, player: "A")
    _ = engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 12), events: [g])
    _ = engine.ingestOthers([snap(.secondHalf, 1, 0, fixture: 99)])

    engine.reset(fixtureId: 1)
    engine.reset(fixtureId: 99)

    // Followed fixture forgot everything: first ingest mid-match re-seeds silently.
    XCTAssertEqual(engine.ingestFollowed(snapshot: snap(.firstHalf, 1, 0, min: 13), events: [g]), [])
    // Others fixture forgot its baseline: this is a fresh first sighting → silent.
    XCTAssertEqual(engine.ingestOthers([snap(.secondHalf, 1, 0, fixture: 99)]), [])
  }
}
