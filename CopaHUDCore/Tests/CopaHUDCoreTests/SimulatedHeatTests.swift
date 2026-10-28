import XCTest
@testable import CopaHUDCore

final class SimulatedHeatTests: XCTestCase {
  private func spot(_ position: String, x: Double, y: Double, id: Int = 7) -> FormationSpot {
    FormationSpot(player: LineupPlayer(name: "P", number: 1, position: position, grid: nil, playerId: id),
                  x: x, y: y)
  }

  func testSamePlayerAlwaysGetsTheSameMap() {
    let s = spot("M", x: 0.5, y: 0.5)
    XCTAssertEqual(SimulatedHeat.points(for: s), SimulatedHeat.points(for: s))
  }

  func testDifferentPlayersGetDifferentMaps() {
    XCTAssertNotEqual(SimulatedHeat.points(for: spot("M", x: 0.5, y: 0.5, id: 7)),
                      SimulatedHeat.points(for: spot("M", x: 0.5, y: 0.5, id: 8)))
  }

  func testPointsStayOnThePitch() {
    for position in ["G", "D", "M", "F"] {
      for p in SimulatedHeat.points(for: spot(position, x: 0.1, y: 0.92)) {
        let onPitch: Bool = p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1
        XCTAssertTrue(onPitch, position)
      }
    }
  }

  func testKeeperStaysInHisOwnEnd() {
    let points = SimulatedHeat.points(for: spot("G", x: 0.5, y: 0.08))
    XCTAssertFalse(points.isEmpty)
    XCTAssertTrue(points.allSatisfy { $0.y < 0.25 })
  }

  func testHeatCentresOnTheFormationSpot() {
    func mean(_ s: FormationSpot) -> (x: Double, y: Double) {
      let p = SimulatedHeat.points(for: s)
      return (p.map(\.x).reduce(0, +) / Double(p.count), p.map(\.y).reduce(0, +) / Double(p.count))
    }
    let forward = mean(spot("F", x: 0.5, y: 0.92))
    let defender = mean(spot("D", x: 0.5, y: 0.36))
    XCTAssertGreaterThan(forward.y, defender.y + 0.3)
    let leftBack = mean(spot("D", x: 0.125, y: 0.36))
    XCTAssertLessThan(leftBack.x, 0.3)
  }

  func testUnknownPositionStillGetsAMap() {
    let s = FormationSpot(player: LineupPlayer(name: "P", number: nil, position: nil, grid: nil, playerId: nil),
                          x: 0.5, y: 0.5)
    XCTAssertFalse(SimulatedHeat.points(for: s).isEmpty)
  }
}
