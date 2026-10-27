import Foundation

/// One starter's place on the formation graph: x 0 (left) … 1 (right),
/// y 0 (own goal) … 1 (attacking end).
public struct FormationSpot: Sendable, Equatable {
  public let player: LineupPlayer
  public let x: Double
  public let y: Double
}

/// Lays a starting XI out by formation. API-Football's `grid` is
/// "row:col" (row 1 = keeper; col 1 = left side); when any starter lacks a
/// usable grid, the whole team falls back to lines by position letter.
public enum FormationLayout {
  public static func spots(_ xi: [LineupPlayer]) -> [FormationSpot] {
    let cells = xi.map(gridCell)
    let keyed: [(player: LineupPlayer, row: Int, col: Int)]
    if cells.allSatisfy({ $0 != nil }) {
      keyed = zip(xi, cells).map { ($0, $1!.row, $1!.col) }
    } else {
      // Lines by position; feed order within a line.
      let lineOf = ["G": 1, "D": 2, "M": 3, "F": 4]
      keyed = xi.enumerated().map { i, p in (p, lineOf[p.position ?? ""] ?? 3, i) }
    }
    let rows = Dictionary(grouping: keyed, by: \.row)
    let rowNumbers = rows.keys.sorted()
    var spots: [FormationSpot] = []
    for (lineIndex, row) in rowNumbers.enumerated() {
      let y = rowNumbers.count == 1 ? 0.5 : 0.08 + 0.84 * Double(lineIndex) / Double(rowNumbers.count - 1)
      let line = rows[row]!.sorted { $0.col < $1.col }
      for (i, entry) in line.enumerated() {
        spots.append(FormationSpot(player: entry.player, x: (Double(i) + 0.5) / Double(line.count), y: y))
      }
    }
    return spots
  }

  private static func gridCell(_ p: LineupPlayer) -> (row: Int, col: Int)? {
    guard let parts = p.grid?.split(separator: ":"), parts.count == 2,
          let row = Int(parts[0]), let col = Int(parts[1]) else { return nil }
    return (row, col)
  }
}
