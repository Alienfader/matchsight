import XCTest
@testable import CopaHUDCore

/// Look at a player: the phone reads shirt numbers from one glasses photo and
/// the lookup only ever answers with someone in the starting XIs.
final class ShirtNumberLookupTests: XCTestCase {
  let ars = Team(id: 42, name: "Arsenal")
  let che = Team(id: 49, name: "Chelsea")

  private var lineups: [Lineup] {
    [Lineup(fixtureId: 1, team: ars, formation: "4-3-3", startXI: [
       LineupPlayer(name: "David Raya", number: 1, position: "G", grid: "1:1"),
       LineupPlayer(name: "B. Saka", number: 7, position: "F", grid: "4:3"),
       LineupPlayer(name: "D. Rice", number: 41, position: "M", grid: "3:2"),
     ], coach: nil),
     Lineup(fixtureId: 1, team: che, formation: "4-2-3-1", startXI: [
       LineupPlayer(name: "E. Martínez", number: 1, position: "G", grid: "1:1"),
       LineupPlayer(name: "C. Palmer", number: 10, position: "M", grid: "4:2"),
     ], coach: nil)]
  }

  private func look(_ candidates: [NumberCandidate]) -> ShirtNumberLookup.Result {
    ShirtNumberLookup.find(candidates, in: lineups)
  }

  func testOneMatchingNumberFindsThePlayer() {
    XCTAssertEqual(look([NumberCandidate(text: "41", weight: 1)]),
                   .player(name: "D. Rice", teamId: 42, index: 2))
  }

  func testTheHeaviestReadableNumberWins() {
    // A big shirt number beats small digits elsewhere in the picture.
    XCTAssertEqual(look([NumberCandidate(text: "41", weight: 0.2),
                         NumberCandidate(text: "10", weight: 0.9)]),
                   .player(name: "C. Palmer", teamId: 49, index: 1))
  }

  func testNumbersNotInEitherLineupAreSkippedForOnesThatAre() {
    XCTAssertEqual(look([NumberCandidate(text: "23", weight: 0.9),
                         NumberCandidate(text: "7", weight: 0.5)]),
                   .player(name: "B. Saka", teamId: 42, index: 1))
  }

  func testTheSameNumberOnBothTeamsIsAmbiguous() {
    XCTAssertEqual(look([NumberCandidate(text: "1", weight: 1)]),
                   .ambiguous(number: 1, names: ["David Raya", "E. Martínez"]))
  }

  func testANumberNobodyWearsSaysSo() {
    XCTAssertEqual(look([NumberCandidate(text: "23", weight: 1)]), .notInLineup(number: 23))
  }

  func testOnlyStandaloneOneOrTwoDigitNumbersCount() {
    // Clocks, scores, words, 100+ and 0 are not shirt numbers.
    XCTAssertEqual(look([NumberCandidate(text: "27:14", weight: 1),
                         NumberCandidate(text: "1-1", weight: 1),
                         NumberCandidate(text: "SAKA", weight: 1),
                         NumberCandidate(text: "123", weight: 1),
                         NumberCandidate(text: "0", weight: 1)]),
                   .noNumber)
    XCTAssertEqual(look([NumberCandidate(text: " 7 ", weight: 1)]),
                   .player(name: "B. Saka", teamId: 42, index: 1))
  }

  func testNoLineupsMeansNothingToMatch() {
    XCTAssertEqual(ShirtNumberLookup.find([NumberCandidate(text: "7", weight: 1)], in: []),
                   .notInLineup(number: 7))
  }

  // MARK: the spoken trigger

  func testLookPhrases() {
    for phrase in ["Who's this?", "who is this", "Who is that player?", "who’s that",
                   "Which player is this?", "who is this guy",
                   // The transcriber's usual mishearings of a short "who's this?".
                   "How is this?", "this?", "Who this?"] {
      XCTAssertTrue(ShirtNumberLookup.isLookRequest(phrase), phrase)
    }
    for phrase in ["Who is Timber?", "Who scored?", "what's the score", "who is this team's captain",
                   "Where is Chelsea from?", "how is this team doing", "is this a penalty?"] {
      XCTAssertFalse(ShirtNumberLookup.isLookRequest(phrase), phrase)
    }
  }
}
