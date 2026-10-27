import XCTest
@testable import CopaHUDCore

final class TeamStyleTests: XCTestCase {
  func testNationKeepsFlagAndNoCrest() {
    let s = TeamStyle.style(for: Team(id: 6, name: "Brazil"))
    XCTAssertEqual(s.code, "BRA"); XCTAssertEqual(s.flag, "🇧🇷"); XCTAssertNil(s.crestURL)
  }

  func testClubUsesTableCodeAndLogo() {
    let logo = URL(string: "https://media.api-sports.io/football/teams/42.png")!
    let s = TeamStyle.style(for: Team(id: 42, name: "Arsenal", logoURL: logo))
    XCTAssertEqual(s.code, "ARS"); XCTAssertEqual(s.flag, ""); XCTAssertEqual(s.crestURL, logo)
  }

  func testApiCodeWinsOverTable() {
    XCTAssertEqual(TeamStyle.style(for: Team(id: 33, name: "Manchester United", code: "MUN")).code, "MUN")
    XCTAssertEqual(TeamStyle.style(for: Team(id: 42, name: "Arsenal", code: "AFC")).code, "AFC")
  }

  func testManchesterClubsDoNotCollide() {
    XCTAssertEqual(TeamStyle.style(for: Team(id: 50, name: "Manchester City")).code, "MCI")
    XCTAssertEqual(TeamStyle.style(for: Team(id: 33, name: "Manchester United")).code, "MUN")
  }

  func testUnknownClubFallsBackToPrefixWithoutFlag() {
    let s = TeamStyle.style(for: Team(id: 327, name: "Bodø/Glimt"))
    XCTAssertEqual(s.code, "BOD"); XCTAssertEqual(s.flag, "")
  }

  func testLogoDoesNotChangeTeamIdentity() {
    let logo = URL(string: "https://media.api-sports.io/football/teams/42.png")!
    XCTAssertEqual(Team(id: 42, name: "Arsenal", code: "ARS", logoURL: logo), Team(id: 42, name: "Arsenal"))
  }
}
