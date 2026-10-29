import Foundation
import CoreGraphics
import MWDATDisplay
import CopaHUDCore

/// Maps a pure `HUDFrame` (from `HUDComposer`) to ONE MWDATDisplay root
/// component. This is the only file that touches the DAT display DSL; all
/// state and string formatting already happened in `CopaHUDCore`, so this
/// layer is a dumb, total function from frame → layout.
///
/// ⚠️ DAT 0.7.0 law (design spec §"Hard-won rules"):
///  • Rule #1 — EXACTLY ONE `.onTap`, on the whole-card root. Any second tap
///    target steals the Neural Band focus ring and pinches fire the wrong
///    action. Every body builder below returns a tapless FlexBox; `build`
///    attaches the single `.onTap` at the very end.
///  • Rule #6 — even passive-looking frames (events list, "no match followed")
///    bind that onTap, or pinches fall through to the Meta launcher.
///  • Rule #4 — `.meta` is the smallest of exactly three styles
///    (heading/body/meta). Density comes from content, not a smaller font.
///
/// Tap-burst counting (1/2/3+) lives in the glasses view model (a 350ms
/// resolve window). This builder wires the
/// ONE resolved callback and nothing else.
enum HUDBuilder {
  /// The single entry point. Builds the toast overlay (when present) above the
  /// body, then binds the one and only `.onTap` on the root card.
  /// The single entry point. Builds the toast overlay (when present) above the
  /// body and binds the one and only `.onTap` on the root card. With DAT 1.0
  /// Inputs active the app reads Neural Band gestures directly (pinch, swipes,
  /// pinch-and-hold) and this tap is only the fallback when Inputs is
  /// unavailable.
  static func build(frame: HUDFrame, onCardTap: @escaping @Sendable () -> Void) -> FlexBox {
    FlexBox(direction: .column, spacing: 4) {
      // Toast overlays the top of whatever body is showing (panel or takeover
      // tail). `opt` turns the optional into a 0-or-1 element loop so the DSL
      // result builder only ever sees `for`/component expressions.
      for toast in opt(frame.toast) {
        Text(toast, style: .meta, color: .secondary)
      }
      bodyComponent(frame.body)
    }.onTap(onCardTap)
  }

  // MARK: - Body dispatch (every HUDFrame.Body case is covered)

  private static func bodyComponent(_ body: HUDFrame.Body) -> FlexBox {
    switch body {
    case let .panel(content):
      return panel(content)
    case let .events(title, lines):
      return list(title: title, lines: lines)
    case let .lineup(content):
      return rosterIndex(content)
    case let .playerCard(content):
      return playerCard(content)
    case let .stats(title, lines):
      return list(title: title, lines: lines)
    case let .otherLive(title, lines):
      return list(title: title, lines: lines)
    case let .takeover(content):
      return takeover(content)
    case let .intro(content):
      return intro(content)
    case let .insight(content):
      return insight(content)
    case let .message(text):
      return message(text)
    case let .quiet(q):
      return message([q.scoreLine, q.clock].compactMap { $0 }.joined(separator: "  "))
    case let .guide(g):
      return message("\(g.action): \(g.result)")
    }
  }

  // MARK: - Bodies (all tapless — the root owns the only onTap)

  /// AMBIENT score pill (after a PSG v ARS reference mock):
  /// `[crest] ARS [ 1  0 ] CHE [crest]` · `⚽ 67'` · `72% ▮▮▮▮▮▮▮▯▯▯ 28%`.
  /// DAT 1.0.1 has no gradients or custom colours, so the frosted look is
  /// the `.card` background and the two-colour bar is the glyph bar.
  private static func panel(_ p: PanelContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 4) {
      pill(p).background(.card).padding(10)
      FlexBox {}.flexGrow(1)
    }
  }

  private static func pill(_ p: PanelContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 4) {
      // Score row: crest + code either side of a boxed score. Nations have no
      // crest and keep their flag next to the code.
      FlexBox(direction: .row, spacing: 8) {
        for url in opt(p.homeCrestURL) {
          Image(uri: url.absoluteString, sizePreset: .icon, cornerRadius: .none)
        }
        Text(HUDFormat.flagged(p.homeFlag, p.homeCode), style: .heading)
        FlexBox {}.flexGrow(1)
        FlexBox(direction: .row) {
          Text("\(p.score.home)  \(p.score.away)", style: .heading)
        }.background(.card).padding(6)
        FlexBox {}.flexGrow(1)
        Text(HUDFormat.flagged(p.awayCode, p.awayFlag), style: .heading)
        for url in opt(p.awayCrestURL) {
          Image(uri: url.absoluteString, sizePreset: .icon, cornerRadius: .none)
        }
      }
      // Clock centred, group label beside it.
      FlexBox(direction: .row, spacing: 8) {
        FlexBox {}.flexGrow(1)
        Text("⚽ \(p.clock)", style: .body)
        for group in opt(p.groupLabel) {
          Text(group, style: .meta, color: .secondary)
        }
        FlexBox {}.flexGrow(1)
      }
      // Two-sided possession (omitted entirely when nil).
      for (home, away) in opt(p.possessionHome.flatMap { h in p.possessionAway.map { (h, $0) } }) {
        FlexBox(direction: .row, spacing: 6) {
          Text("\(home)%", style: .meta, color: .secondary)
          FlexBox {
            Text(HUDFormat.possessionBar(home: home), style: .meta)
          }.flexGrow(1)
          Text("\(away)%", style: .meta, color: .secondary)
        }
      }
      // Status row: "· stale ·" left, 🔕 (cinema mode) right.
      FlexBox(direction: .row) {
        for _ in when(p.isStale) {
          Text("· stale ·", style: .meta, color: .secondary)
        }
        FlexBox {}.flexGrow(1)
        for _ in when(p.alertsPaused) {
          Text("🔕", style: .meta)
        }
      }
    }
  }

  /// INTRO: both crests large side by side, "ARS v CHE", the competition.
  /// Crests are .fill in half-width boxes with the same horizontal inset the
  /// player card uses, so the height stays bounded and nothing scrolls.
  private static func intro(_ i: IntroContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 6) {
      FlexBox {}.flexGrow(1)
      FlexBox(direction: .row, spacing: 12) {
        crestBox(url: i.homeCrestURL, fallback: HUDFormat.flagged(i.homeFlag, i.homeCode))
        crestBox(url: i.awayCrestURL, fallback: HUDFormat.flagged(i.awayCode, i.awayFlag))
      }
      Text("\(i.homeCode) v \(i.awayCode)", style: .heading)
      for competition in opt(i.competition) {
        Text(competition, style: .meta, color: .secondary)
      }
      FlexBox {}.flexGrow(1)
    }
  }

  private static func crestBox(url: URL?, fallback: String) -> FlexBox {
    FlexBox(direction: .column) {
      for u in opt(url) {
        Image(uri: u.absoluteString, sizePreset: .fill, cornerRadius: .none)
      }
      for _ in when(url == nil) {
        Text(fallback, style: .heading)
      }
    }.flexGrow(1).padding(.horizontal, crestInset)
  }

  /// Horizontal inset (points per side) on intro crests — keeps two .fill
  /// crests short enough to sit above the title without scrolling.
  private static let crestInset: CGFloat = 36

  /// TAKEOVER: headline centered with flexGrow spacers, score, detail —
  /// with the protagonist's headshot beside the headline when the feed
  /// knows the player (goal scorer / sent-off player). Image is NOT a tap
  /// target — rule #1 stands, the root owns the only onTap.
  private static func takeover(_ t: TakeoverContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 6) {
      FlexBox {}.flexGrow(1)
      FlexBox(direction: .row, spacing: 10) {
        for url in opt(t.imageURL) {
          Image(uri: url, sizePreset: .icon, cornerRadius: .medium)
        }
        Text(t.headline, style: .heading)
        FlexBox {}.flexGrow(1)
      }
      Text(t.scoreLine, style: .body)
      for detail in opt(t.detail) {
        Text(detail, style: .meta, color: .secondary)
      }
      FlexBox {}.flexGrow(1)
    }
  }

  /// STARTING XI card (Champions League demo style, remade): team line on
  /// top, face on the left, light first name over bold surname with the
  /// "#7 · FWD" line beneath, compact dot strip + n/11 counter in the
  /// footer. The image is NOT a tap target (rule #1).
  private static func playerCard(_ c: PlayerCardContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 6) {
      Text(c.teamLine, style: .meta, color: .secondary)
      // DAT 0.7.0 Image has only .icon / .fill and NO size field. A .fill image
      // fills its container's WIDTH; height follows the source aspect (player
      // headshots are ~square). On the ~square Ray-Ban Display plate a full-width
      // image is also full-HEIGHT, so it overflows the team line + name + footer
      // and the user has to scroll. The height-share (flexGrow) lever barely
      // helps because height tracks WIDTH, not the band's height. So bound the
      // WIDTH instead: symmetric horizontal padding narrows the image, and its
      // height shrinks with it. Tune kImageInset — larger = smaller face.
      FlexBox(direction: .row, crossAlignment: .center) {
        for url in opt(c.photoURL) {
          Image(uri: url, sizePreset: .fill, cornerRadius: .medium)
        }
      }.padding(EdgeInsets(leading: kImageInset, trailing: kImageInset))
      FlexBox(direction: .column, spacing: 2, crossAlignment: .center) {
        for first in opt(c.firstName.isEmpty ? nil : c.firstName) {
          Text(first, style: .body, color: .secondary)
        }
        Text(c.lastName, style: .heading)
        Text(numberLine(c), style: .body)
      }
      FlexBox {}.flexGrow(1)
      FlexBox(direction: .row) {
        Text(c.dots, style: .meta, color: .secondary)
        FlexBox {}.flexGrow(1)
        Text(c.counter, style: .meta, color: .secondary)
      }
    }
  }

  /// Horizontal inset (points per side) on the player-card headshot. .fill sizes
  /// the image to its container WIDTH and the height tracks that, so this inset
  /// is the real size lever on the ~square Ray-Ban plate: bigger inset → narrower
  /// and shorter face that fits above the name without scrolling.
  private static let kImageInset: CGFloat = 110

  /// "#7 · FWD" (position omitted when the feed doesn't know it).
  private static func numberLine(_ c: PlayerCardContent) -> String {
    if let position = c.positionLabel { return "#\(c.number) · \(position)" }
    return "#\(c.number)"
  }

  /// STARTING XI index card (carousel front page) — also renders the honest
  /// "lineup not available" fallback: title, grouped XI rows, coach, and a
  /// centered pinch hint so the band gesture is discoverable.
  private static func rosterIndex(_ c: LineupContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 2) {
      Text(c.title, style: .body)
      for row in c.rows {
        Text(row, style: .meta)
      }
      for coach in opt(c.coachLine) {
        Text(coach, style: .meta, color: .secondary)
      }
      FlexBox {}.flexGrow(1)
      for footer in opt(c.footer) {
        FlexBox(direction: .row) {
          FlexBox {}.flexGrow(1)
          Text(footer, style: .meta, color: .secondary)
          FlexBox {}.flexGrow(1)
        }
      }
    }
  }

  /// EVENTS / LINEUP / OTHER LIVE: title row + `.meta` lines.
  private static func list(title: String, lines: [String]) -> FlexBox {
    FlexBox(direction: .column, spacing: 2) {
      Text(title, style: .body)
      for line in lines {
        Text(line, style: .meta)
      }
      FlexBox {}.flexGrow(1)
    }
  }

  /// AI INSIGHT: title, the insight itself, and an honest source footer
  /// ("Muse Spark · inferred" / "Data only"). Tapless like every body.
  private static func insight(_ c: InsightContent) -> FlexBox {
    FlexBox(direction: .column, spacing: 4) {
      Text(c.title, style: .body)
      Text(c.body, style: .body)
      FlexBox {}.flexGrow(1)
      Text(c.footer, style: .meta, color: .secondary)
    }
  }

  /// MESSAGE: idle / pre-kickoff / error text.
  private static func message(_ text: String) -> FlexBox {
    FlexBox(direction: .column) {
      Text(text, style: .body)
      FlexBox {}.flexGrow(1)
    }
  }

  // MARK: - Result-builder helpers
  //
  // The DAT DSL result builder supports `for` loops (buildArray); these turn an
  // optional / bool into a 0-or-1 element sequence so conditional content stays
  // inside that proven path without relying on `if`/`if let` support.

  private static func opt<T>(_ value: T?) -> [T] {
    value.map { [$0] } ?? []
  }

  private static func when(_ condition: Bool) -> [Void] {
    condition ? [()] : []
  }
}
