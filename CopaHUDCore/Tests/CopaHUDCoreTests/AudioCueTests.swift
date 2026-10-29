import XCTest
@testable import CopaHUDCore

/// Sounds through the glasses' speakers, so a goal isn't missed while the
/// fan watches the TV, and the analyst's answers read aloud.
final class AudioCueTests: XCTestCase {
  let bra = Team(id: 6, name: "Brazil")

  private func moment(_ kind: MatchMoment.Kind) -> MatchMoment {
    MatchMoment(fixtureId: 1, kind: kind, score: ScoreLine(home: 1, away: 0), minute: 10)
  }

  func testEachAlertHasItsSound() {
    XCTAssertEqual(AudioCue.for(moment(.goal(scorer: nil, assist: nil, detail: .normal))), .goal)
    XCTAssertEqual(AudioCue.for(moment(.goal(scorer: "A", assist: nil, detail: .ownGoal))), .goal)
    XCTAssertEqual(AudioCue.for(moment(.redCard(player: "A", team: bra))), .redCard)
    XCTAssertEqual(AudioCue.for(moment(.penaltyAwarded(team: bra))), .varCheck)
    XCTAssertEqual(AudioCue.for(moment(.varDecision(.goalOverturned))), .varCheck)
    XCTAssertEqual(AudioCue.for(moment(.halfTime)), .whistle)
    XCTAssertEqual(AudioCue.for(moment(.fullTime)), .whistle)
  }

  func testOtherMatchesStayQuiet() {
    let snap = MatchSnapshot(fixtureId: 9, home: bra, away: bra, score: ScoreLine(home: 1, away: 0),
                             status: .firstHalf, elapsedMinutes: 10, possessionHome: nil,
                             groupLabel: nil, kickoff: Date())
    XCTAssertNil(AudioCue.for(moment(.otherMatchGoal(snapshot: snap, scorer: nil))))
  }

  func testOnlyTheLoudestOfABurstPlays() {
    // A goal and full time in one poll: one sound, the goal.
    XCTAssertEqual(AudioCue.loudest([moment(.fullTime), moment(.goal(scorer: nil, assist: nil, detail: .normal))]),
                   .goal)
    XCTAssertNil(AudioCue.loudest([]))
  }

  // MARK: spoken answers

  func testTheSpokenAnswerIsTheTitleThenTheBody() {
    let c = InsightContent(title: "INTER LEAD DESPITE PRESSURE",
                           body: "Internacional lead 1–0 via Alan Patrick in the 46th.",
                           footer: "Muse Spark · observed", question: "who's winning?")
    XCTAssertEqual(SpokenAnswer.text(c),
                   "Inter lead despite pressure. Internacional lead 1–0 via Alan Patrick in the 46th.")
  }

  func testStepsAndEmptyAnswersAreNotSpoken() {
    XCTAssertNil(SpokenAnswer.text(InsightContent(title: "Thinking…", body: "", footer: "Muse Spark",
                                                  question: "who scored?")))
    XCTAssertNil(SpokenAnswer.text(InsightContent(title: "", body: "", footer: "")))
  }

  func testEmojiAreLeftOut() {
    let c = InsightContent(title: "⚽ Goal rush", body: "Three goals in 🔥 ten minutes.", footer: "x")
    XCTAssertEqual(SpokenAnswer.text(c), "Goal rush. Three goals in ten minutes.")
  }
}
