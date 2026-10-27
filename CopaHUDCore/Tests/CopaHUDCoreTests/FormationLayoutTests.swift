import XCTest
@testable import CopaHUDCore

/// Places a starting XI on the glasses' formation graph: x 0 (left) … 1
/// (right), y 0 (own goal) … 1 (attacking end).
final class FormationLayoutTests: XCTestCase {

  private func p(_ name: String, _ pos: String, _ grid: String?) -> LineupPlayer {
    LineupPlayer(name: name, number: nil, position: pos, grid: grid)
  }

  /// API-Football's 4-3-3, in the feed's order (keeper, then each line right-to-left: col 4 first).
  private var fourThreeThree: [LineupPlayer] {
    [p("Raya", "G", "1:1"),
     p("White", "D", "2:4"), p("Saliba", "D", "2:3"), p("Gabriel", "D", "2:2"), p("Calafiori", "D", "2:1"),
     p("Rice", "M", "3:3"), p("Zubimendi", "M", "3:2"), p("Ødegaard", "M", "3:1"),
     p("Saka", "F", "4:3"), p("Gyökeres", "F", "4:2"), p("Martinelli", "F", "4:1")]
  }

  func testGridRowsBecomeLinesFromOwnGoalUp() throws {
    let spots = FormationLayout.spots(fourThreeThree)
    XCTAssertEqual(spots.count, 11)
    let gk = try XCTUnwrap(spots.first { $0.player.name == "Raya" })
    XCTAssertEqual(gk.x, 0.5, accuracy: 0.001)
    let defenders = spots.filter { $0.player.position == "D" }
    let forwards = spots.filter { $0.player.position == "F" }
    XCTAssertEqual(Set(defenders.map(\.y)).count, 1, "one line")
    XCTAssertLessThan(gk.y, defenders[0].y)
    XCTAssertLessThan(defenders[0].y, forwards[0].y)
  }

  func testColumnsSpreadEvenlyInGridOrder() {
    let defenders = FormationLayout.spots(fourThreeThree)
      .filter { $0.player.position == "D" }.sorted { $0.x < $1.x }
    XCTAssertEqual(defenders.map(\.player.name), ["Calafiori", "Gabriel", "Saliba", "White"])
    XCTAssertEqual(defenders.map(\.x), [0.125, 0.375, 0.625, 0.875])
  }

  func testWithoutGridFallsBackToPositionLines() {
    let xi = [p("A", "G", nil), p("B", "D", nil), p("C", "D", nil), p("D", "M", nil), p("E", "F", nil)]
    let spots = FormationLayout.spots(xi)
    XCTAssertEqual(spots.count, 5)
    let ys = ["A", "B", "D", "E"].map { n in spots.first { $0.player.name == n }!.y }
    XCTAssertEqual(ys, ys.sorted(), "keeper, defence, midfield, attack — upwards")
    XCTAssertEqual(spots.filter { $0.player.position == "D" }.map(\.x).sorted(), [0.25, 0.75])
  }

  func testOneBadGridFallsBackForTheWholeTeam() {
    var xi = fourThreeThree
    xi[5] = p("Rice", "M", "x")
    let mids = FormationLayout.spots(xi).filter { $0.player.position == "M" }
    XCTAssertEqual(mids.count, 3)
    XCTAssertEqual(Set(mids.map(\.y)).count, 1)
  }
}
