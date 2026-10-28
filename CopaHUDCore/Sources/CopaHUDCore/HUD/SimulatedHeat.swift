import Foundation

/// A point on the player card's mini pitch, same axes as `FormationSpot`.
public struct HeatPoint: Sendable, Equatable {
  public let x: Double
  public let y: Double
}

/// SIMULATED heat for the scripted demo only — the feed has no positional
/// data, so a real match never shows this. A cloud around the player's
/// formation spot, shaped by role, seeded by player id so every redraw of
/// the same player looks the same. Always labelled "SIMULATED" on screen.
public enum SimulatedHeat {
  public static func points(for spot: FormationSpot, count: Int = 40) -> [HeatPoint] {
    var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(spot.player.playerId ?? 0)) &+ 0x9E37_79B9)
    let wide = spot.x < 0.3 || spot.x > 0.7
    let (cx, cy, sx, sy): (Double, Double, Double, Double)
    switch spot.player.position {
    case "G": (cx, cy, sx, sy) = (spot.x, min(spot.y, 0.12), 0.08, 0.035)
    case "D" where wide: (cx, cy, sx, sy) = (spot.x, spot.y + 0.1, 0.06, 0.17)
    case "D": (cx, cy, sx, sy) = (spot.x, spot.y, 0.1, 0.09)
    case "M": (cx, cy, sx, sy) = (spot.x, spot.y, 0.14, 0.13)
    case "F": (cx, cy, sx, sy) = (spot.x, spot.y - 0.05, 0.15, 0.09)
    default: (cx, cy, sx, sy) = (spot.x, spot.y, 0.15, 0.15)
    }
    let maxY = spot.player.position == "G" ? 0.22 : 0.97
    return (0..<count).map { _ in
      HeatPoint(x: clamp(cx + sx * rng.bell(), 0.03, 0.97),
                y: clamp(cy + sy * rng.bell(), 0.03, maxY))
    }
  }

  private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}

/// SplitMix64: tiny, deterministic across runs and platforms.
struct SeededGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }

  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }

  /// Roughly normal in about -1.5…1.5 (sum of three uniforms).
  mutating func bell() -> Double { (next() + next() + next() - 1.5) }
}
