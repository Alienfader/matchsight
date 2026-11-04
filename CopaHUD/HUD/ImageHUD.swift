import SwiftUI
import UIKit
import CopaHUDCore

/// Phone-drawn HUD pages in the spatial-glass language: translucent frosted
/// surfaces, an icy-cyan → sky → lavender → lilac gradient, soft white type,
/// generous rounding. The DAT display DSL can't draw any of it, so every page
/// is drawn here with SwiftUI and sent as one picture
/// (`MWDATDisplay.Image(image:)`). HUDBuilder's DSL layouts remain the
/// fallback if a drawing fails.
///
/// The glasses add light: black is see-through, so "translucent glass" is a
/// partly transparent fill and the room shows through for real.
///
/// Pictures render at 360×360 (scale 0.6 of the 600-pt layout): on hardware
/// that sent in ~0.33 s against ~0.9 s at 600×600, and text stayed crisp.
enum ImageHUD {
  static let renderScale: CGFloat = 0.6
  /// Settings → Brightness: every page is drawn at this fraction of its light.
  static var brightness: Double = 1
  /// Settings → Style → Mono: the Dark glass pages in white and greys.
  /// Colour stays where it carries meaning (crests, yellow and red cards).
  static var mono = false
  /// Mono, on the pages that keep the classic look (goal banner, intro,
  /// messages): drawn in greyscale.
  static var greyscale = false

  @MainActor static func scorePanel(_ p: PanelContent, toast: String?, deck: DeckPosition?,
                                    homeCrest: UIImage?, awayCrest: UIImage?) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      if p.isPreMatch {
        PreMatchCapsule(p: p, homeCrest: homeCrest, awayCrest: awayCrest)
      } else {
        LiveScoreCapsule(p: p, homeCrest: homeCrest, awayCrest: awayCrest)
      }
    }, deck: deck)
  }

  @MainActor static func carousel(xi: [LineupPlayer], index: Int, teamLine: String,
                                  counter: String, toast: String?, deck: DeckPosition?,
                                  photos: @escaping (Int) -> UIImage?, stats: [Int: PlayerStats]) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      PlayerCardStack(xi: xi, index: index, teamLine: teamLine, counter: counter,
                      photos: photos, stats: stats)
    }, deck: deck)
  }

  @MainActor static func playerDetail(player: LineupPlayer, photo: UIImage?, stats: PlayerStats?,
                                      spot: FormationSpot?, heat: [HeatPoint]?, scripted: Bool,
                                      teamLine: String, counter: String, toast: String?,
                                      deck: DeckPosition?) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      PlayerDetailPage(player: player, photo: photo, stats: stats, spot: spot, heat: heat,
                       scripted: scripted, teamLine: teamLine, counter: counter)
    }, deck: deck)
  }

  @MainActor static func insight(_ c: InsightContent, toast: String?, score: CompactScore?,
                                 deck: DeckPosition?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { InsightPage(c: c) }, deck: deck)
  }

  /// Events, Stats and Other Live: a titled list of pre-formatted lines.
  @MainActor static func list(title: String, lines: [String], toast: String?, score: CompactScore?,
                              deck: DeckPosition?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { ListPage(title: title, lines: lines) }, deck: deck)
  }

  /// The STARTING XI board (first card of a lineup page): the formation when
  /// the XI is known, else the text rows ("lineup not available").
  @MainActor static func roster(_ c: LineupContent, xi: [LineupPlayer]?, opponent: [LineupPlayer]?, isHome: Bool,
                                crest: UIImage?, photos: @escaping (Int) -> UIImage?, stats: [Int: PlayerStats],
                                toast: String?, deck: DeckPosition?) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      FormationBoard(c: c, xi: xi, opponent: opponent, isHome: isHome, crest: crest, photos: photos, stats: stats)
    }, deck: deck)
  }

  @MainActor static func takeover(_ t: TakeoverContent, photo: UIImage?, score: CompactScore?) -> UIImage? {
    render(PageFrame(toast: nil, score: score) { CelebrationPage(t: t, photo: photo) })
  }

  @MainActor static func intro(_ i: IntroContent, homeCrest: UIImage?, awayCrest: UIImage?) -> UIImage? {
    render(PageFrame(toast: nil, score: nil) {
      MatchupCapsule(homeName: i.homeCode, awayName: i.awayCode,
                     homeFlag: i.homeFlag, awayFlag: i.awayFlag,
                     homeCrest: homeCrest, awayCrest: awayCrest,
                     lower: i.competition.map { [$0] } ?? [])
    })
  }

  @MainActor static func message(_ text: String, toast: String?, score: CompactScore?,
                                 deck: DeckPosition?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { MessagePage(text: text) }, deck: deck)
  }

  /// First-run gesture guide: one gesture per page, big and plain.
  @MainActor static func guide(_ g: GuideContent, toast: String?) -> UIImage? {
    render(GuidePage(g: g, toast: toast))
  }

  /// Battery saver: black except one dim line, so almost nothing is lit.
  @MainActor static func quiet(_ q: QuietContent) -> UIImage? {
    render(QuietPage(content: q))
  }

  /// Deck pages carry the page dots along the bottom edge.
  @MainActor private static func render(_ view: some View, deck: DeckPosition? = nil) -> UIImage? {
    let page = view.frame(width: 600, height: 600)
      .overlay(alignment: .bottom) { if let deck { PageDots(deck: deck).padding(.bottom, 8) } }
    let r = ImageRenderer(content: page.background(.black).saturation(greyscale ? 0 : 1)
      .colorMultiply(Color(white: brightness)))
    r.scale = renderScale
    return r.uiImage
  }
}

/// The followed match in one line (compact scoreboard on deck pages).
struct ScoreSummary {
  let homeCode: String
  let awayCode: String
  let score: ScoreLine
  let homeCrestURL: URL?
  let awayCrestURL: URL?
}

/// A ScoreSummary with its crests resolved, ready to draw.
struct CompactScore {
  let summary: ScoreSummary
  let homeCrest: UIImage?
  let awayCrest: UIImage?
}

/// Crests and headshots for the phone-drawn pages, fetched once and kept.
@MainActor final class RemoteImageCache {
  private var images: [URL: UIImage] = [:]
  private var loading: Set<URL> = []

  func image(_ url: URL?) -> UIImage? { url.flatMap { images[$0] } }

  /// Starts any missing downloads; `onLoad` runs after each one lands.
  func prefetch(_ urls: [URL?], onLoad: @escaping @MainActor () -> Void) {
    for case let url? in urls where images[url] == nil && !loading.contains(url) {
      loading.insert(url)
      Task { [weak self] in
        let data = try? await URLSession.shared.data(from: url).0
        guard let self else { return }
        self.loading.remove(url)
        if let data, let img = UIImage(data: data) {
          self.images[url] = img
          onLoad()
        }
      }
    }
  }
}

// MARK: - Palette and glass material

private enum Palette {
  static let ice = Color(hex: 0xC8F1FF)
  static let cyan = Color(hex: 0x88DFFF)
  static let sky = Color(hex: 0x6DCFFF)
  static let periwinkle = Color(hex: 0xA9CBFF)
  static let lavender = Color(hex: 0xC9BCFF)
  static let lilac = Color(hex: 0xD9C4F4)
  static let mist = Color(hex: 0xF7FBFF)
  static let smoke = Color(hex: 0x94A5C1)
  static let smokyLavender = Color(hex: 0x9291B0)
  static let violet = Color(hex: 0x797394)
  static let probabilityCyan = Color(hex: 0x54C8FF)
  static let softPurple = Color(hex: 0xBBAAFF)
  static let coral = Color(hex: 0xFF526D)
  static let mint = Color(hex: 0xB9FFD3)
  static let captain = Color(hex: 0xFFE55B)

  /// The signature left-to-right gradient.
  static let signature = [ice, sky, lavender, lilac]
}

private extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
  }
}

/// Layered translucent glass: the tint gradient, a white sheen from the
/// upper-left, a violet shade toward the lower-right, a hairline rim and a
/// broad soft glow.
private struct Glass: View {
  enum Tint { case signature, sky, smoky, dark, mint }
  var tint: Tint = .signature
  var radius: CGFloat = 28
  var opacity: Double = 0.5

  private var colors: [Color] {
    switch tint {
    case .signature: return Palette.signature
    case .sky: return [Palette.ice, Palette.cyan, Palette.sky, Palette.probabilityCyan]
    case .smoky: return [Palette.smoke, Palette.smokyLavender]
    case .dark: return [Palette.violet, Palette.smokyLavender, Palette.violet]
    case .mint: return [Palette.mint, Palette.cyan, Palette.lavender]
    }
  }

  private var glow: Color {
    switch tint {
    case .mint: return Palette.mint
    case .dark, .smoky: return Palette.lavender
    default: return Palette.cyan
    }
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    ZStack {
      shape.fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        .opacity(opacity)
      shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                startPoint: .topLeading, endPoint: .center))
      shape.fill(LinearGradient(colors: [.clear, Palette.violet.opacity(0.28)],
                                startPoint: .center, endPoint: .bottomTrailing))
      shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.18)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
                         lineWidth: 1.5)
    }
    .shadow(color: glow.opacity(0.35), radius: 22)
  }
}

private struct Crest: View {
  let image: UIImage?
  let fallback: String
  var size: CGFloat = 64

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2)
          .overlay(Text(fallback.prefix(1)).font(.system(size: size * 0.42, weight: .bold)))
      }
    }
    .frame(width: size, height: size)
    .shadow(color: .white.opacity(0.25), radius: 6)
  }
}

private enum Face {
  static func surname(_ name: String) -> String { HUDFormat.splitName(name).last }
}

// MARK: - Page chrome

/// Toast line and/or the compact scoreboard above the page content.
private struct PageFrame<Content: View>: View {
  let toast: String?
  let score: CompactScore?
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 14) {
      if let score { CompactScoreboard(score: score) }
      if let toast {
        Text(toast).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
          .lineLimit(1).minimumScaleFactor(0.6)
      }
      content()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 22)
  }
}

/// One dot per deck page, the current one a wider bar. Every gesture that
/// reaches the app lights the bar cyan for a moment, so a swipe the band
/// never sent reads as "try again", not "broken".
private struct PageDots: View {
  let deck: DeckPosition

  var body: some View {
    HStack(spacing: 9) {
      ForEach(0..<deck.count, id: \.self) { i in
        if i == deck.index {
          Capsule().fill(deck.pulse && !ImageHUD.mono ? Palette.cyan : .white)
            .frame(width: 26, height: 9)
            .shadow(color: deck.pulse ? (ImageHUD.mono ? .white : Palette.cyan) : .clear, radius: 6)
        } else {
          Circle().fill(.white.opacity(0.45)).frame(width: 9, height: 9)
        }
      }
    }
  }
}

private struct CompactScoreboard: View {
  let score: CompactScore

  var body: some View {
    HStack(spacing: 12) {
      Crest(image: score.homeCrest, fallback: score.summary.homeCode, size: 34)
      Text(score.summary.homeCode).font(.system(size: 22, weight: .bold))
      Text("\(score.summary.score.home)  \(score.summary.score.away)")
        .font(.system(size: 24, weight: .heavy))
        .padding(.horizontal, 12).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.55), lineWidth: 1.2))
      Text(score.summary.awayCode).font(.system(size: 22, weight: .bold))
      Crest(image: score.awayCrest, fallback: score.summary.awayCode, size: 34)
    }
    .padding(.horizontal, 22).padding(.vertical, 10)
    .background(Glass(radius: 36, opacity: 0.45))
  }
}

// MARK: - Score capsules

/// Two-section capsule: a bright pill on top, a frostier smoky band below,
/// with a clear gap so they read as two separate bubbles.
private struct TwoSectionCapsule<Top: View, Lower: View>: View {
  @ViewBuilder let top: () -> Top
  @ViewBuilder let lower: () -> Lower

  var body: some View {
    VStack(spacing: 12) {
      top()
        .frame(maxWidth: .infinity).frame(height: 132)
        .background(Glass(tint: .signature, radius: 56, opacity: 0.55))
        .overlay(alignment: .topLeading) { Streaks().clipShape(Capsule()) }
      lower()
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 26)
        .background(Glass(tint: .smoky, radius: 30, opacity: 0.4).padding(.horizontal, 22))
    }
  }
}

/// Barely-there curved light reflections inside the capsule.
private struct Streaks: View {
  var body: some View {
    GeometryReader { g in
      Path { p in
        p.move(to: CGPoint(x: g.size.width * 0.08, y: g.size.height * 0.85))
        p.addQuadCurve(to: CGPoint(x: g.size.width * 0.42, y: g.size.height * 0.12),
                       control: CGPoint(x: g.size.width * 0.18, y: g.size.height * 0.2))
        p.move(to: CGPoint(x: g.size.width * 0.6, y: g.size.height * 0.9))
        p.addQuadCurve(to: CGPoint(x: g.size.width * 0.95, y: g.size.height * 0.3),
                       control: CGPoint(x: g.size.width * 0.85, y: g.size.height * 0.85))
      }
      .stroke(.white.opacity(0.12), lineWidth: 1.2)
    }
  }
}

/// Team names, crests and VS — the intro and pre-match top row.
private struct MatchupCapsule: View {
  let homeName: String
  let awayName: String
  let homeFlag: String
  let awayFlag: String
  let homeCrest: UIImage?
  let awayCrest: UIImage?
  let lower: [String]
  var probability: WinProbability? = nil

  var body: some View {
    VStack(spacing: 18) {
      TwoSectionCapsule {
        HStack(spacing: 14) {
          Text(HUDFormat.flagged(homeFlag, homeName)).font(.system(size: 30, weight: .heavy))
            .lineLimit(1).minimumScaleFactor(0.6)
          Crest(image: homeCrest, fallback: homeName, size: 70)
          Text("VS").font(.system(size: 18, weight: .bold)).opacity(0.85)
          Crest(image: awayCrest, fallback: awayName, size: 70)
          Text(HUDFormat.flagged(awayName, awayFlag)).font(.system(size: 30, weight: .heavy))
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 26)
      } lower: {
        VStack(spacing: 4) {
          ForEach(lower, id: \.self) { line in
            Text(line).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
          }
        }
      }
      if let probability {
        ProbabilityBar(p: probability, home: homeName, away: awayName, captioned: true)
          .padding(.horizontal, 30)
      }
    }
  }
}

/// Before kickoff: matchup, kickoff date and time, the prediction.
private struct PreMatchCapsule: View {
  let p: PanelContent
  let homeCrest: UIImage?
  let awayCrest: UIImage?

  private var when: String {
    guard let kickoff = p.kickoff else { return p.clock }
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM, HH:mm"
    return f.string(from: kickoff)
  }

  var body: some View {
    MatchupCapsule(homeName: p.homeCode, awayName: p.awayCode,
                   homeFlag: p.homeFlag, awayFlag: p.awayFlag,
                   homeCrest: homeCrest, awayCrest: awayCrest,
                   lower: [when] + (p.groupLabel.map { [$0.uppercased()] } ?? []),
                   probability: p.prediction)
  }
}

/// In play: crests, codes, boxed score; clock, possession and timeline below.
private struct LiveScoreCapsule: View {
  let p: PanelContent
  let homeCrest: UIImage?
  let awayCrest: UIImage?

  private var clock: String {
    switch p.clock {
    case "FT": return "FULL TIME"
    case "HT": return "HALF TIME"
    default: return p.clock
    }
  }

  var body: some View {
    VStack(spacing: 14) {
      if let label = p.groupLabel {
        Text(label.uppercased()).font(.system(size: 17, weight: .semibold)).opacity(0.8)
      }
      TwoSectionCapsule {
        HStack(spacing: 12) {
          Crest(image: homeCrest, fallback: p.homeCode, size: 66)
          Text(p.homeCode).font(.system(size: 30, weight: .heavy))
            .lineLimit(1).minimumScaleFactor(0.6)
          Spacer(minLength: 4)
          // The score never wraps or shrinks; the codes give way instead.
          HStack(spacing: 18) {
            Text("\(p.score.home)")
            Rectangle().fill(.white.opacity(0.45)).frame(width: 1.2, height: 34)
            Text("\(p.score.away)")
          }
          .font(.system(size: 40, weight: .heavy))
          .lineLimit(1)
          .fixedSize()
          .padding(.horizontal, 16).padding(.vertical, 4)
          .background(RoundedRectangle(cornerRadius: 13)
            .fill(.white.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.6), lineWidth: 1.3)))
          .layoutPriority(1)
          Spacer(minLength: 4)
          Text(p.awayCode).font(.system(size: 30, weight: .heavy))
            .lineLimit(1).minimumScaleFactor(0.6)
          Crest(image: awayCrest, fallback: p.awayCode, size: 66)
        }
        .padding(.horizontal, 26)
      } lower: {
        VStack(spacing: 10) {
          HStack(spacing: 8) {
            if p.alertsPaused { Image(systemName: "bell.slash.fill") }
            Image(systemName: "soccerball")
            Text(clock)
            if p.isStale { Text("· STALE").opacity(0.75) }
          }
          .font(.system(size: 21, weight: .semibold))
          if let home = p.possessionHome, let away = p.possessionAway {
            PossessionBar(home: home, away: away)
          }
          TimelineBar(markers: p.timeline, elapsed: p.elapsedMinutes)
        }
      }
    }
  }
}

/// Three-way prediction bar: home cyan, draw lavender, away coral.
private struct ProbabilityBar: View {
  let p: WinProbability
  let home: String
  let away: String
  var captioned = false

  private var caption: String {
    switch p.favourite {
    case .home: return "\(p.home)% chance \(home) to win"
    case .away: return "\(p.away)% chance \(away) to win"
    case nil: return "\(p.home)% · draw \(p.draw)% · \(p.away)%"
    }
  }

  var body: some View {
    VStack(spacing: 8) {
      if captioned {
        Text(caption).font(.system(size: 19, weight: .semibold))
      }
      GeometryReader { g in
        let total = CGFloat(max(1, p.home + p.draw + p.away))
        HStack(spacing: 2) {
          Capsule().fill(ImageHUD.mono ? .white : Palette.probabilityCyan).frame(width: g.size.width * CGFloat(p.home) / total)
          if p.draw > 0 {
            Capsule().fill(ImageHUD.mono ? Color(hex: 0xA1A1AA) : Palette.softPurple).frame(width: g.size.width * CGFloat(p.draw) / total)
          }
          Capsule().fill(ImageHUD.mono ? Color(hex: 0x52525B) : Palette.coral)
        }
      }
      .frame(height: 11)
      .shadow(color: Palette.cyan.opacity(0.5), radius: 6)
      HStack {
        Text("\(p.home)%")
        Spacer()
        Text("draw \(p.draw)%").opacity(0.75)
        Spacer()
        Text("\(p.away)%")
      }
      .font(.system(size: 16, weight: .semibold))
      Text("API-Football prediction").font(.system(size: 13, weight: .medium)).opacity(0.6)
    }
  }
}

private struct PossessionBar: View {
  let home: Int
  let away: Int

  var body: some View {
    HStack(spacing: 10) {
      Text("\(home)%").font(.system(size: 16, weight: .semibold))
      GeometryReader { g in
        HStack(spacing: 2) {
          Capsule().fill(ImageHUD.mono ? .white : Palette.probabilityCyan).frame(width: g.size.width * CGFloat(home) / 100)
          Capsule().fill(ImageHUD.mono ? Color(hex: 0x52525B) : Palette.coral)
        }
      }
      .frame(height: 8)
      Text("\(away)%").font(.system(size: 16, weight: .semibold))
    }
  }
}

private struct TimelineBar: View {
  let markers: [TimelineMarker]
  let elapsed: Int?

  var body: some View {
    GeometryReader { g in
      let w = g.size.width
      let knob = elapsed.map { TimelineMarker.fraction(minute: $0, elapsed: $0) } ?? 0
      ZStack(alignment: .topLeading) {
        ForEach(Array(markers.enumerated()), id: \.offset) { _, m in
          icon(m).position(x: w * TimelineMarker.fraction(minute: m.minute, elapsed: elapsed), y: 9)
        }
        Capsule()
          .fill(LinearGradient(colors: [Palette.probabilityCyan, Palette.softPurple, Palette.coral],
                               startPoint: .leading, endPoint: .trailing))
          .opacity(0.45)
          .frame(height: 6).offset(y: 24)
        Capsule().fill(.white.opacity(0.85))
          .frame(width: max(8, w * knob), height: 6).offset(y: 24)
        Circle().fill(.white).frame(width: 14, height: 14)
          .shadow(color: .white, radius: 4)
          .position(x: max(7, min(w - 7, w * knob)), y: 27)
      }
    }
    .frame(height: 36)
  }

  @ViewBuilder private func icon(_ m: TimelineMarker) -> some View {
    switch m.kind {
    case .goal: Image(systemName: "soccerball").font(.system(size: 14, weight: .bold))
    case .yellowCard: RoundedRectangle(cornerRadius: 2).fill(Palette.captain).frame(width: 9, height: 13)
    case .redCard: RoundedRectangle(cornerRadius: 2).fill(Palette.coral).frame(width: 9, height: 13)
    case .varCheck: Image(systemName: "tv").font(.system(size: 13, weight: .bold))
    }
  }
}

// MARK: - Starting XI: player cards

private struct PlayerCardStack: View {
  let xi: [LineupPlayer]
  let index: Int
  let teamLine: String
  let counter: String
  let photos: (Int) -> UIImage?
  let stats: [Int: PlayerStats]

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text(teamLine).lineLimit(1).minimumScaleFactor(0.6)
        Spacer()
        Text(counter)
      }
      .font(.system(size: 20, weight: .semibold)).opacity(0.85)
      ZStack {
        Text("STARTING XI")
          .font(.system(size: 78, weight: .heavy)).kerning(-1.5)
          .opacity(0.08).lineLimit(1).minimumScaleFactor(0.5)
        ForEach(neighbours, id: \.self) { i in
          card(i, focused: false)
            .scaleEffect(0.92)
            .blur(radius: 4)
            .opacity(0.3)
            .offset(x: CGFloat(i - index) * 150)
        }
        card(index, focused: true)
      }
      .frame(height: 450)
    }
  }

  private var neighbours: [Int] {
    [index - 1, index + 1].filter { xi.indices.contains($0) }
  }

  private func card(_ i: Int, focused: Bool) -> some View {
    let p = xi[i]
    return PlayerCard(player: p, photo: p.playerId.flatMap(photos),
                      stats: p.playerId.flatMap { stats[$0] })
  }
}

/// Tall portrait card: name top-left, big headshot fading into the glass,
/// huge number bottom-left, captain badge, a slim live-stats strip.
private struct PlayerCard: View {
  let player: LineupPlayer
  let photo: UIImage?
  let stats: PlayerStats?

  private var names: (first: String, last: String) { HUDFormat.splitName(player.name) }
  private var positionLabel: String {
    ["G": "GK", "D": "DEF", "M": "MID", "F": "FWD"][player.position ?? ""] ?? ""
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Glass(tint: .sky, radius: 26, opacity: 0.55)
      portrait
        .frame(width: 270, height: 300)
        .offset(x: 15, y: 98)
      VStack(alignment: .leading, spacing: 0) {
        if !names.first.isEmpty {
          Text(names.first).font(.system(size: 24, weight: .medium)).opacity(0.9)
        }
        Text(names.last).font(.system(size: 36, weight: .heavy)).kerning(-0.5)
          .lineLimit(1).minimumScaleFactor(0.5)
        Text(positionLabel).font(.system(size: 18, weight: .semibold)).opacity(0.8)
      }
      .padding(.top, 22).padding(.horizontal, 22)
      VStack(spacing: 6) {
        Spacer()
        HStack(alignment: .bottom) {
          Text(player.number.map(String.init) ?? "")
            .font(.system(size: 72, weight: .heavy)).kerning(-2)
            .shadow(color: Palette.sky.opacity(0.8), radius: 8)
          Spacer()
          if stats?.isCaptain == true {
            Text("C").font(.system(size: 22, weight: .heavy)).foregroundStyle(.black)
              .frame(width: 34, height: 34)
              .background(RoundedRectangle(cornerRadius: 8).fill(Palette.captain))
              .padding(.bottom, 14)
          }
        }
        StatStrip(stats: stats)
      }
      .padding(.horizontal, 20).padding(.bottom, 16)
    }
    .frame(width: 300, height: 450)
  }

  @ViewBuilder private var portrait: some View {
    if let photo {
      Image(uiImage: photo).resizable().scaledToFill()
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .mask(LinearGradient(stops: [.init(color: .white, location: 0.0),
                                     .init(color: .white, location: 0.55),
                                     .init(color: .clear, location: 0.95)],
                             startPoint: .top, endPoint: .bottom))
    } else {
      Image(systemName: "person.fill").resizable().scaledToFit()
        .padding(40).opacity(0.75)
        .mask(LinearGradient(colors: [.white, .clear], startPoint: .center, endPoint: .bottom))
    }
  }
}

/// Live per-player counters ("--" until the feed has them).
private struct StatStrip: View {
  let stats: PlayerStats?

  var body: some View {
    HStack(spacing: 0) {
      cell("PAS", stats?.passes)
      cell("SH", stats?.shots)
      cell("TK", stats?.tackles)
      cell("INT", stats?.interceptions)
    }
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.14)))
  }

  private func cell(_ label: String, _ value: Int?) -> some View {
    VStack(spacing: 0) {
      Text(value.map(String.init) ?? "--").font(.system(size: 20, weight: .bold))
      Text(label).font(.system(size: 12, weight: .semibold)).opacity(0.75)
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Starting XI: player detail (pinch on a card)

/// The focused player's match in full: headshot, name, rating and minutes,
/// then every figure the feed sent, two columns.
private struct PlayerDetailPage: View {
  let player: LineupPlayer
  let photo: UIImage?
  let stats: PlayerStats?
  let spot: FormationSpot?
  let heat: [HeatPoint]?
  /// Demo mode: the figures are scripted, and the card says so.
  let scripted: Bool
  let teamLine: String
  let counter: String

  private var names: (first: String, last: String) { HUDFormat.splitName(player.name) }
  private var rows: [PlayerStatRow] { HUDFormat.playerDetailRows(stats, position: player.position) }
  private var subtitle: String {
    let position = ["G": "GK", "D": "DEF", "M": "MID", "F": "FWD"][player.position ?? ""]
    return [player.number.map { "#\($0)" }, position].compactMap { $0 }.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(teamLine).lineLimit(1).minimumScaleFactor(0.6)
        Spacer()
        Text(counter)
      }
      .font(.system(size: 20, weight: .semibold)).opacity(0.85)
      HStack(spacing: 18) {
        Group {
          if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
          } else {
            Image(systemName: "person.fill").resizable().scaledToFit().padding(22).opacity(0.75)
          }
        }
        .frame(width: 110, height: 110).clipShape(Circle())
        .overlay(Circle().strokeBorder(Palette.sky, lineWidth: 2))
        VStack(alignment: .leading, spacing: 2) {
          if !names.first.isEmpty {
            Text(names.first).font(.system(size: 22, weight: .medium)).opacity(0.9)
          }
          Text(names.last).font(.system(size: 36, weight: .heavy)).kerning(-0.5)
            .lineLimit(1).minimumScaleFactor(0.5)
          Text(subtitle).font(.system(size: 19, weight: .semibold)).opacity(0.8)
          if let summary = HUDFormat.playerSummary(stats) {
            Text(scripted ? "\(summary) · scripted" : summary)
              .font(.system(size: 19, weight: .bold)).foregroundStyle(Palette.sky)
              .lineLimit(1).minimumScaleFactor(0.7)
          }
        }
        Spacer(minLength: 0)
        if let spot { MiniPitch(spot: spot, heat: heat) }
      }
      if rows.isEmpty {
        Text("No match stats for this player yet")
          .font(.system(size: 22, weight: .medium)).opacity(0.75)
          .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
      } else {
        // Three columns: a full outfield card (nine figures) is three rows,
        // so the card stays inside the frame with the page dots below it.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                  alignment: .leading, spacing: 10) {
          ForEach(rows, id: \.label) { row in
            VStack(alignment: .leading, spacing: 0) {
              Text(row.value).font(.system(size: 24, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.55)
              Text(row.label.uppercased()).font(.system(size: 13, weight: .semibold)).opacity(0.75)
            }
          }
        }
      }
      Text("pinch to close · swipe for next player")
        .font(.system(size: 15, weight: .medium)).opacity(0.6)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(22)
    .background(Glass(tint: .sky, radius: 26, opacity: 0.45))
  }
}

/// The player's place on a small pitch, lying west to east like the TV
/// picture: his own goal on the left, attacking to the right. Demo mode adds
/// a SIMULATED heat cloud; a real match shows only the formation spot,
/// because the feed has no positional data.
private struct MiniPitch: View {
  let spot: FormationSpot
  let heat: [HeatPoint]?

  var body: some View {
    VStack(spacing: 4) {
      GeometryReader { g in
        let w = g.size.width, h = g.size.height
        ZStack {
          if let heat {
            ForEach(Array(heat.enumerated()), id: \.offset) { _, p in
              Circle()
                .fill(RadialGradient(colors: ImageHUD.mono ? [.white.opacity(0.5), .white.opacity(0.15), .clear]
                                       : [Palette.coral.opacity(0.55), Palette.captain.opacity(0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: 16))
                .frame(width: 32, height: 32)
                .position(WestToEast.point(x: p.x, y: p.y, w, h))
            }
            .blendMode(.plusLighter)
          }
          PitchLines(westToEast: true).stroke(.white.opacity(0.5), lineWidth: 1.2)
          Circle().fill(.white).frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(ImageHUD.mono ? Color(hex: 0x71717A) : Palette.sky, lineWidth: 2))
            .position(spot.westToEast(w, h))
        }
      }
      .frame(width: 160, height: 112)
      Text(heat == nil ? "POSITION" : "SIMULATED")
        .font(.system(size: 12, weight: .heavy)).kerning(0.5)
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(Capsule().fill(.white.opacity(heat == nil ? 0.12 : 0.22)))
    }
  }
}

// MARK: - Starting XI: formation board

private struct FormationBoard: View {
  let c: LineupContent
  let xi: [LineupPlayer]?
  let opponent: [LineupPlayer]?
  let isHome: Bool
  let crest: UIImage?
  let photos: (Int) -> UIImage?
  let stats: [Int: PlayerStats]

  /// "Arsenal · 4-3-3" → "4-3-3".
  private var formation: String? {
    c.title.components(separatedBy: " · ").dropFirst().first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Crest(image: crest, fallback: c.title, size: 36)
        Text("STARTING XI").font(.system(size: 24, weight: .heavy))
        Spacer()
        if let formation { Text(formation).font(.system(size: 24, weight: .heavy)) }
      }
      if let xi, !xi.isEmpty {
        LinePitch(spots: FormationLayout.spots(xi), opponent: opponent.map(FormationLayout.spots),
                  isHome: isHome, photos: photos, stats: stats)
          .frame(height: 400)
      } else {
        ForEach(Array(c.rows.enumerated()), id: \.offset) { _, row in
          Text(row).font(.system(size: 21)).lineLimit(1).minimumScaleFactor(0.5)
        }
      }
      if let footer = c.footer {
        Text(footer).font(.system(size: 16, weight: .medium)).opacity(0.75)
          .frame(maxWidth: .infinity, alignment: .center)
      }
    }
    .padding(20)
    .background(Glass(tint: .signature, radius: 22, opacity: 0.38))
  }
}

/// Line-art pitch over the glass, lying west to east like the TV picture,
/// with both teams in their halves: home on the left attacking right, away
/// on the right attacking left. The page's team is a small headshot with
/// number and surname; the other team is a dim number.
private struct LinePitch: View {
  let spots: [FormationSpot]
  let opponent: [FormationSpot]?
  let isHome: Bool
  let photos: (Int) -> UIImage?
  let stats: [Int: PlayerStats]

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      ZStack {
        PitchLines(westToEast: true).stroke(.white.opacity(0.45), lineWidth: 1.5)
        ForEach(Array((opponent ?? []).enumerated()), id: \.offset) { _, spot in
          OpponentMark(number: spot.player.number)
            .position(spot.inHalf(home: !isHome, w, h))
        }
        ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
          FormationPlayer(player: spot.player,
                          photo: spot.player.playerId.flatMap(photos),
                          isCaptain: spot.player.playerId.flatMap { stats[$0] }?.isCaptain == true)
            .position(spot.inHalf(home: isHome, w, h))
        }
      }
    }
  }
}

/// Full pitch geometry: outline, halfway line, centre circle, both boxes.
/// Upright (goals top and bottom), or turned a quarter left to lie west to
/// east (goals left and right).
private struct PitchLines: Shape {
  var westToEast = false

  func path(in r: CGRect) -> Path {
    guard westToEast else { return upright(in: r) }
    // Draw upright in the swapped rectangle, then turn it: (x, y) → (y, height − x).
    let turn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: r.minX, ty: r.minY + r.height)
    return upright(in: CGRect(x: 0, y: 0, width: r.height, height: r.width)).applying(turn)
  }

  private func upright(in r: CGRect) -> Path {
    var p = Path()
    p.addRoundedRect(in: r, cornerSize: CGSize(width: 8, height: 8))
    p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
    let cr = r.width * 0.13
    p.addEllipse(in: CGRect(x: r.midX - cr, y: r.midY - cr, width: cr * 2, height: cr * 2))
    for top in [true, false] {
      let boxW = r.width * 0.56, boxH = r.height * 0.14
      let goalW = r.width * 0.26, goalH = r.height * 0.055
      let y = top ? r.minY : r.maxY - boxH
      let gy = top ? r.minY : r.maxY - goalH
      p.addRect(CGRect(x: r.midX - boxW / 2, y: y, width: boxW, height: boxH))
      p.addRect(CGRect(x: r.midX - goalW / 2, y: gy, width: goalW, height: goalH))
    }
    return p
  }
}

private struct FormationPlayer: View {
  let player: LineupPlayer
  let photo: UIImage?
  let isCaptain: Bool

  var body: some View {
    VStack(spacing: 2) {
      ZStack(alignment: .bottomTrailing) {
        Group {
          if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
          } else {
            Image(systemName: "person.fill").resizable().scaledToFit().padding(9).opacity(0.8)
          }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1.2))
        .shadow(color: Palette.cyan.opacity(0.6), radius: 5)
        Text(player.number.map(String.init) ?? "")
          .font(.system(size: 13, weight: .heavy))
          .padding(.horizontal, 4)
          .background(Capsule().fill(Palette.sky.opacity(0.85)))
          .offset(x: 6, y: 3)
        if isCaptain {
          Text("C").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black)
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.captain))
            .offset(x: -36, y: 3)
        }
      }
      // Lines sit about 72 pt apart in a half pitch, so names stay narrow.
      Text(Face.surname(player.name))
        .font(.system(size: 17, weight: .heavy))
        .lineLimit(1).minimumScaleFactor(0.55)
        .frame(width: 70)
    }
  }
}

// MARK: - Celebration (goal / red card / VAR takeovers)

private struct CelebrationPage: View {
  let t: TakeoverContent
  let photo: UIImage?

  private enum Kind { case goal, red, video, other }
  /// The content carries no kind, so read the headline.
  private var kind: Kind {
    let h = t.headline.uppercased()
    if h.contains("VAR") { return .video }
    if h.contains("RED") || h.contains("🟥") { return .red }
    if h.contains("GO") { return .goal }
    return .other
  }

  private var glow: Color {
    switch kind {
    case .goal: return Palette.mint
    case .red: return Palette.coral
    case .video, .other: return Palette.cyan
    }
  }

  private var headline: String {
    // The ⚽ is drawn as a separate glowing ball after the word.
    t.headline.replacingOccurrences(of: "⚽", with: "").trimmingCharacters(in: .whitespaces)
  }

  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 8) {
        Text(headline)
          .font(.system(size: 62, weight: .heavy)).kerning(-1)
          .lineLimit(1).minimumScaleFactor(0.45)
          .shadow(color: glow, radius: 14)
          .shadow(color: glow.opacity(0.6), radius: 28)
        if kind == .goal {
          Image(systemName: "soccerball").font(.system(size: 50, weight: .bold))
            .shadow(color: Palette.mint, radius: 12)
        }
      }
      Text(t.scoreLine).font(.system(size: 28, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
      if t.detail != nil || photo != nil {
        HStack(spacing: 14) {
          if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
              .frame(width: 70, height: 70).clipShape(Circle())
              .overlay(Circle().strokeBorder(glow, lineWidth: 2.5))
              .shadow(color: glow, radius: 10)
          }
          if let detail = t.detail {
            Text(detail).font(.system(size: 22, weight: .semibold))
              .lineLimit(2).minimumScaleFactor(0.6)
          }
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Glass(tint: kind == .goal ? .mint : .signature, radius: 40, opacity: 0.35))
      }
    }
    // Clear of the headline's glow, so the scoreboard above stays readable.
    .padding(.top, 22)
    // Behind, not in, the layout: a fixed 560 pt shower would push the page
    // past 600 pt and crop the scoreboard.
    .background { if kind == .goal { Confetti() } }
  }
}

/// A light shower of small mint / white / yellow-green pieces (fixed layout,
/// so every redraw of the same takeover looks identical).
private struct Confetti: View {
  private static let pieces: [(x: CGFloat, y: CGFloat, r: Double, c: Int)] = (0..<34).map { i in
    let x = CGFloat((i * 97) % 560) + 20
    let y = CGFloat((i * 53) % 520) + 30
    return (x, y, Double((i * 37) % 180), i % 4)
  }
  private static let colors = [Color.white, Palette.mint, Color(hex: 0xC8FF8C), Color(hex: 0xA6F5C0)]

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(0..<Self.pieces.count, id: \.self) { i in
        let piece = Self.pieces[i]
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Self.colors[piece.c])
          .frame(width: 9, height: 5)
          .rotationEffect(.degrees(piece.r))
          .opacity(0.75)
          .position(x: piece.x, y: piece.y)
      }
    }
    .frame(width: 560, height: 560)
  }
}

// MARK: - AI Insight, lists, messages

private struct CardTitle: View {
  let icon: String
  let title: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: icon).shadow(color: Palette.cyan, radius: 6)
      Text(title.uppercased()).lineLimit(1).minimumScaleFactor(0.6)
    }
    .font(.system(size: 24, weight: .heavy))
  }
}

private struct InsightPage: View {
  let c: InsightContent

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      // The transcript, so the fan sees what was heard before the answer.
      if let question = c.question {
        Text("\u{201C}\(question)\u{201D}")
          .font(.system(size: 22, weight: .semibold)).opacity(0.8)
          .lineLimit(2).minimumScaleFactor(0.7)
      }
      CardTitle(icon: "sparkles", title: c.title)
      // Bodies are ≤ 150 characters (MatchInsight.maxBody): about six
      // lines at 34 pt, so the shrink is only a safety margin.
      if !c.body.isEmpty {
        Text(c.body)
          .font(.system(size: 34, weight: .medium))
          .lineSpacing(2).minimumScaleFactor(0.85)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(c.footer)
        .font(.system(size: 18, weight: .semibold))
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.2))
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Glass(tint: .signature, radius: 26, opacity: 0.4))
  }
}

private struct ListPage: View {
  let title: String
  let lines: [String]

  private var icon: String {
    switch title {
    case "Events": return "list.bullet"
    case "Other Live": return "dot.radiowaves.left.and.right"
    default: return "chart.bar.fill"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CardTitle(icon: icon, title: title)
      ForEach(Array(lines.prefix(8).enumerated()), id: \.offset) { _, line in
        ListRow(line: line)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Glass(tint: .dark, radius: 22, opacity: 0.38))
  }
}

/// One list line. Stats lines ("SHOTS  5 · 3") split into label and values;
/// the possession line draws a real two-colour bar.
private struct ListRow: View {
  let line: String

  var body: some View {
    let parts = line.components(separatedBy: "  ").filter { !$0.isEmpty }
    Group {
      if parts.first == "POSS", let pct = Int(parts.last?.dropLast() ?? "") {
        HStack(spacing: 10) {
          Text("POSS").opacity(0.75)
          PossessionBar(home: pct, away: 100 - pct)
        }
      } else if parts.count == 2 {
        HStack {
          Text(parts[0]).opacity(0.75)
          Spacer()
          Text(parts[1]).bold()
        }
      } else {
        Text(line).lineLimit(1).minimumScaleFactor(0.6)
      }
    }
    .font(.system(size: 23, weight: .medium))
    .padding(.vertical, 2)
  }
}

private struct GuidePage: View {
  let g: GuideContent
  let toast: String?

  var body: some View {
    VStack(spacing: 10) {
      Spacer(minLength: 0)
      if let toast {
        Text(toast).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
      }
      VStack(spacing: 18) {
        HStack {
          Text("GESTURES").font(.system(size: 20, weight: .heavy)).foregroundStyle(Palette.cyan)
          Spacer()
          Text("\(g.step)/\(g.total)").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.ice.opacity(0.62))
        }
        Image(systemName: g.icon).font(.system(size: 88, weight: .semibold)).foregroundStyle(Palette.cyan)
          .shadow(color: Palette.cyan.opacity(0.6), radius: 10)
          .frame(height: 120)
        Text(g.action).font(.system(size: 44, weight: .heavy))
        Text(g.result).font(.system(size: 26, weight: .medium)).foregroundStyle(Palette.ice.opacity(0.8))
          .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        Spacer(minLength: 0)
        Text(g.tryAgain ? "Not that one. Try: \(g.action.lowercased())" : "Try it now")
          .font(.system(size: 20, weight: .bold))
          .foregroundStyle(g.tryAgain ? Palette.captain : Palette.ice.opacity(0.62))
      }
      .padding(22)
      .frame(width: 556, height: 420)
      .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0x07111C).opacity(0.78))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
          .strokeBorder(Palette.cyan.opacity(0.6), lineWidth: 1.5)))
      Color.clear.frame(height: 9)
    }
    .foregroundStyle(.white)
    .padding(.bottom, 14)
  }
}

private struct QuietPage: View {
  let content: QuietContent

  var body: some View {
    let line = [content.scoreLine, content.clock.isEmpty ? nil : content.clock]
      .compactMap { $0 }.joined(separator: "   ")
    Text(line.isEmpty ? "Matchsight" : line)
      .font(.system(size: 30, weight: .semibold)).monospacedDigit()
      .foregroundStyle(Palette.smoke.opacity(0.55))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(.top, 40)
  }
}

private struct MessagePage: View {
  let text: String

  var body: some View {
    Text(text).font(.system(size: 30, weight: .semibold))
      .multilineTextAlignment(.center).minimumScaleFactor(0.6)
      .padding(28)
      .frame(maxWidth: .infinity)
      .background(Glass(tint: .signature, radius: 40, opacity: 0.4))
  }
}

// MARK: - Dark glass (Settings → HUD style)
//
// One card for every page: the same size and place, a score strip on top,
// a near-black fill that adds almost no light, bright type. Goal banners,
// the crest intro and the quiet page keep their own look.

extension ImageHUD {
  @MainActor static func darkLive(_ p: PanelContent, latest: [LatestEvent], momentum: Momentum?,
                                  score: CompactScore?, toast: String?, deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: p.clock, toast: toast, deck: deck,
                    flags: DarkFlags(stale: p.isStale, paused: p.alertsPaused)) {
      if p.isPreMatch { DarkPreMatch(p: p) } else { DarkLive(p: p, latest: latest, momentum: momentum) }
    })
  }

  @MainActor static func darkStory(_ c: InsightContent, score: CompactScore?, clock: String,
                                   toast: String?, deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: clock, toast: toast, deck: deck) { DarkStory(c: c) })
  }

  @MainActor static func darkEvents(_ latest: [LatestEvent], score: CompactScore?, clock: String,
                                    toast: String?, deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: clock, toast: toast, deck: deck) {
      DarkHeading(title: "Events", note: latest.isEmpty ? nil : "\(latest.count)").padding(.bottom, 10)
      if latest.isEmpty { DarkNote(text: "No goals or cards yet") }
      ForEach(Array(latest.prefix(5).enumerated()), id: \.offset) { i, e in
        DarkEventRow(e: e, homeCode: score?.summary.homeCode, last: i == min(latest.count, 5) - 1)
      }
    })
  }

  @MainActor static func darkList(title: String, lines: [String], score: CompactScore?, clock: String,
                                  toast: String?, deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: clock, toast: toast, deck: deck) {
      if title == "Other Live" { DarkOtherLive(lines: lines) } else { DarkStats(lines: lines, score: score) }
    })
  }

  /// The XI board; `focus` highlights the carousel's player.
  @MainActor static func darkBoard(xi: [LineupPlayer], opponent: [LineupPlayer]?, isHome: Bool, focus: Int?,
                                   teamName: String, formation: String?,
                                   score: CompactScore?, clock: String, toast: String?,
                                   deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: clock, toast: toast, deck: deck) {
      DarkBoard(xi: xi, opponent: opponent, isHome: isHome, focus: focus, teamName: teamName, formation: formation)
    })
  }

  @MainActor static func darkPlayer(player: LineupPlayer, photo: UIImage?, stats: PlayerStats?,
                                    spot: FormationSpot?, heat: [HeatPoint]?,
                                    scripted: Bool, counter: String, score: CompactScore?, clock: String,
                                    toast: String?, deck: DeckPosition?) -> UIImage? {
    render(DarkCard(score: score, clock: clock, toast: toast, deck: deck) {
      DarkPlayer(player: player, photo: photo, stats: stats, spot: spot, heat: heat,
                 scripted: scripted, counter: counter)
    })
  }

  @MainActor static func deckTakeover(_ t: TakeoverContent, score: CompactScore?) -> UIImage? {
    render(DeckTakeover(t: t, score: score))
  }

  @MainActor static func deckIntro(_ i: IntroContent, homeCrest: UIImage?, awayCrest: UIImage?) -> UIImage? {
    render(DeckIntro(i: i, homeCrest: homeCrest, awayCrest: awayCrest))
  }

  @MainActor static func deckMessage(_ text: String) -> UIImage? {
    render(DeckMessage(text: text))
  }
}

/// The two deck looks from the redesign. Mono (A): black, white and greys,
/// the page fills the lens with a thin rule under the score. Dark glass (B):
/// a glass card with a cyan glow, cyan for the home side and lavender for
/// the away side. Crests and yellow/red cards keep their colour in both.
private enum Dark {
  static var a: Bool { ImageHUD.mono }
  static var ink: Color { a ? .white : Color(hex: 0xF2F5F9) }
  /// Secondary values: the clock, the away score, minutes.
  static var soft: Color { a ? Color(hex: 0xC9CDD3) : Color(hex: 0xA7B0BC) }
  /// Labels.
  static var dim: Color { a ? Color(hex: 0x8B9097) : Color(hex: 0x7A8390) }
  /// The rule under the score.
  static var rule: Color { a ? Color(hex: 0x343438) : .white.opacity(0.08) }
  /// Hairlines between rows.
  static var hair: Color { a ? Color(hex: 0x232326) : .white.opacity(0.08) }
  static var accent: Color { a ? .white : Color(hex: 0x5FE3F0) }
  static var home: Color { a ? .white : Color(hex: 0x5FE3F0) }
  static var away: Color { a ? Color(hex: 0xC9CDD3) : Color(hex: 0xB9A6FF) }
  static var clock: Color { a ? Color(hex: 0xC9CDD3) : Color(hex: 0x5FE3F0) }
  static var dot: Color { a ? Color(hex: 0x3A3A3E) : .white.opacity(0.18) }
  static let mono = Font.Design.monospaced
  /// The page's own background: plain black, or black with B's soft glow.
  @ViewBuilder static var backdrop: some View {
    if a { Color.black } else {
      RadialGradient(colors: [Color(hex: 0x5FE3F0).opacity(0.10), .clear], center: UnitPoint(x: 0.5, y: 0.36),
                     startRadius: 0, endRadius: 400)
        .background(Color.black)
    }
  }
  static func side(_ code: String, home: String?) -> Color {
    a ? dim : (code == home ? Dark.home : Dark.away)
  }
}

private struct DarkFlags {
  var stale = false
  var paused = false
}

/// Every deck page: the toast pill on top, the score header, the page, the dots.
private struct DarkCard<Content: View>: View {
  let score: CompactScore?
  let clock: String
  let toast: String?
  let deck: DeckPosition?
  var flags = DarkFlags()
  @ViewBuilder let content: () -> Content

  var body: some View {
    ZStack(alignment: .top) {
      Dark.backdrop
      VStack(spacing: 0) {
        if Dark.a {
          page.padding(.horizontal, 40)
        } else {
          page
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .overlay(alignment: .top) {
              LinearGradient(colors: [.clear, Dark.accent, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1).padding(.horizontal, 28)
            }
            .padding(.horizontal, 28)
        }
        DeckDots(deck: deck).padding(.top, 14)
      }
      .padding(.top, 44).padding(.bottom, Dark.a ? 26 : 24)
      if let toast {
        Text(toast).font(.system(size: 17, weight: .regular, design: Dark.mono))
          .foregroundStyle(Dark.a ? Dark.soft : Dark.accent).lineLimit(1).minimumScaleFactor(0.6)
          .padding(.horizontal, 14).padding(.vertical, 5)
          .background(Capsule().fill(.black.opacity(Dark.a ? 1 : 0.6)))
          .overlay(Capsule().strokeBorder(Dark.a ? Dark.rule : Dark.accent.opacity(0.5), lineWidth: 1))
          .padding(.top, 8).padding(.horizontal, 30)
      }
    }
    .foregroundStyle(Dark.ink)
  }

  private var page: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let score {
        DarkStrip(score: score, clock: clock, flags: flags)
          .padding(.bottom, 16)
          .overlay(alignment: .bottom) { Rectangle().fill(Dark.rule).frame(height: 1) }
      }
      VStack(alignment: .leading, spacing: 0) { content() }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

private struct DeckDots: View {
  let deck: DeckPosition?

  var body: some View {
    HStack(spacing: 10) {
      if let deck {
        ForEach(0..<deck.count, id: \.self) { i in
          Circle().fill(i == deck.index ? Dark.accent : Dark.dot).frame(width: 7, height: 7)
            .shadow(color: i == deck.index && !Dark.a ? Dark.accent.opacity(0.7) : .clear, radius: 5)
        }
      }
    }
    .frame(height: 8).frame(maxWidth: .infinity)
  }
}

/// Crest, code, score, code, crest; the clock on the right.
private struct DarkStrip: View {
  let score: CompactScore
  let clock: String
  let flags: DarkFlags

  var body: some View {
    let s = score.summary
    HStack(spacing: 12) {
      Crest(image: score.homeCrest, fallback: s.homeCode, size: 32)
      code(s.homeCode)
      goals(s.score.home)
      Text("–").font(.system(size: 24, design: Dark.mono)).foregroundStyle(Dark.dim)
      goals(s.score.away)
      code(s.awayCode)
      Crest(image: score.awayCrest, fallback: s.awayCode, size: 32)
      Spacer(minLength: 4)
      if flags.paused { Image(systemName: "bell.slash").font(.system(size: 20)).foregroundStyle(Dark.dim) }
      if flags.stale { Text("stale").font(.system(size: 16, design: Dark.mono)).foregroundStyle(Palette.coral) }
      HStack(spacing: 8) {
        if !Dark.a {
          Circle().fill(Dark.accent).frame(width: 7, height: 7).shadow(color: Dark.accent.opacity(0.8), radius: 5)
        }
        Text(clock).font(.system(size: Dark.a ? 30 : 26, design: Dark.mono)).foregroundStyle(Dark.clock)
          .lineLimit(1).minimumScaleFactor(0.6)
      }
    }
  }

  private func code(_ c: String) -> some View {
    Text(c).font(.system(size: Dark.a ? 22 : 20, weight: .semibold)).tracking(Dark.a ? 0 : 1)
      .foregroundStyle(Dark.a ? Dark.ink : Dark.soft)
  }

  private func goals(_ n: Int) -> some View {
    Text("\(n)").font(.system(size: Dark.a ? 40 : 44, weight: .medium, design: Dark.mono)).padding(.horizontal, 3)
  }
}

/// A label row: what this is on the left, a quieter note on the right.
private struct DarkHeading: View {
  let title: String
  var note: String? = nil
  var icon: String? = nil

  var body: some View {
    HStack(spacing: 10) {
      if let icon { Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Dark.a ? Dark.dim : Dark.accent) }
      Text(title).font(.system(size: 18)).foregroundStyle(Dark.a ? Dark.dim : Dark.soft)
      Spacer(minLength: 4)
      if let note { Text(note).font(.system(size: 16)).foregroundStyle(Dark.dim).lineLimit(1) }
    }
  }
}

private struct DarkNote: View {
  let text: String
  var body: some View { Text(text).font(.system(size: 22)).foregroundStyle(Dark.dim).padding(.top, 10) }
}

/// A two-sided bar: the home share filled, the rest the away side's.
private struct ShareBar: View {
  let share: Double

  var body: some View {
    GeometryReader { g in
      if Dark.a {
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2).strokeBorder(Dark.rule, lineWidth: 1)
          RoundedRectangle(cornerRadius: 1).fill(Dark.ink)
            .frame(width: max(0, (g.size.width - 4) * share)).padding(2)
        }
      } else {
        HStack(spacing: 2) {
          Capsule().fill(Dark.home).frame(width: max(4, (g.size.width - 2) * share))
          Capsule().fill(Dark.away.opacity(0.55))
        }
        .padding(.vertical, 2)
      }
    }
    .frame(height: 12)
  }
}

private struct SideBar: View {
  let homeCode: String
  let awayCode: String
  let share: Double

  var body: some View {
    HStack(spacing: 12) {
      Text(homeCode).font(.system(size: 16, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.ink : Dark.home)
        .frame(width: 44, alignment: .leading)
      ShareBar(share: share)
      Text(awayCode).font(.system(size: 16, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.soft : Dark.away)
        .frame(width: 44, alignment: .trailing)
    }
  }
}

private struct DarkLive: View {
  let p: PanelContent
  let latest: [LatestEvent]
  let momentum: Momentum?

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      if let momentum {
        VStack(alignment: .leading, spacing: 12) {
          DarkHeading(title: "Momentum, last 10 minutes", note: "shots and corners")
          SideBar(homeCode: p.homeCode, awayCode: p.awayCode,
                  share: DeckFormat.share(home: momentum.home, away: momentum.away))
        }
      } else if let home = p.possessionHome {
        VStack(alignment: .leading, spacing: 12) {
          DarkHeading(title: "Possession", note: "\(home)% · \(100 - home)%")
          SideBar(homeCode: p.homeCode, awayCode: p.awayCode, share: Double(home) / 100)
        }
      }
      VStack(alignment: .leading, spacing: 0) {
        DarkHeading(title: "Latest").padding(.bottom, 10)
        if latest.isEmpty { DarkNote(text: "No goals or cards yet") }
        ForEach(Array(latest.prefix(3).enumerated()), id: \.offset) { i, e in
          DarkEventRow(e: e, homeCode: p.homeCode, last: i == min(latest.count, 3) - 1)
        }
      }
    }
  }
}

private struct DarkPreMatch: View {
  let p: PanelContent

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      DarkHeading(title: "Kickoff")
      Text(p.clock).font(.system(size: 64, weight: .medium, design: Dark.mono))
      if let w = p.prediction {
        DarkHeading(title: "Win probability")
        HStack(spacing: 28) {
          prob(p.homeCode, w.home)
          prob("Draw", w.draw)
          prob(p.awayCode, w.away)
        }
      }
    }
  }

  private func prob(_ label: String, _ value: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(value)%").font(.system(size: 32, weight: .medium, design: Dark.mono))
      Text(label).font(.system(size: 16)).foregroundStyle(Dark.dim)
    }
  }
}

private struct DarkEventRow: View {
  let e: LatestEvent
  let homeCode: String?
  var last = false

  var body: some View {
    HStack(spacing: 16) {
      Text(e.minute.replacingOccurrences(of: "'", with: "′"))
        .font(.system(size: 20, design: Dark.mono)).foregroundStyle(Dark.soft)
        .lineLimit(1).minimumScaleFactor(0.7).frame(width: 56, alignment: .leading)
      icon.frame(width: 24)
      Text(e.name).font(.system(size: 23)).lineLimit(1).minimumScaleFactor(0.7)
      Spacer(minLength: 4)
      Text(e.team).font(.system(size: 16, design: Dark.mono)).foregroundStyle(Dark.side(e.team, home: homeCode))
    }
    .frame(height: 56)
    .overlay(alignment: .top) { Rectangle().fill(Dark.hair).frame(height: 1) }
    .overlay(alignment: .bottom) { if last { Rectangle().fill(Dark.hair).frame(height: 1) } }
  }

  @ViewBuilder private var icon: some View {
    switch e.kind {
    case .goal, .penalty: Image(systemName: "soccerball").font(.system(size: 21, weight: .light))
    case .ownGoal: Image(systemName: "soccerball").font(.system(size: 21, weight: .light)).foregroundStyle(Dark.dim)
    case .missedPenalty: Image(systemName: "xmark.circle").font(.system(size: 20, weight: .light)).foregroundStyle(Dark.dim)
    case .yellow: RoundedRectangle(cornerRadius: 2).fill(Palette.captain).frame(width: 12, height: 18)
    case .red: RoundedRectangle(cornerRadius: 2).fill(Palette.coral).frame(width: 12, height: 18)
    case .varCheck: Image(systemName: "tv").font(.system(size: 19, weight: .light))
    }
  }
}

/// Team stats: possession as a bar, then one row per figure, home left.
private struct DarkStats: View {
  let lines: [String]
  let score: CompactScore?

  var body: some View {
    let rows = lines.compactMap(DeckFormat.statRow)
    VStack(alignment: .leading, spacing: 0) {
      if let poss = lines.lazy.compactMap(DeckFormat.possession).first {
        HStack {
          Text(score?.summary.homeCode ?? "Home")
          Spacer()
          Text("Possession")
          Spacer()
          Text(score?.summary.awayCode ?? "Away")
        }
        .font(.system(size: 18)).foregroundStyle(Dark.dim).padding(.bottom, 10)
        HStack(spacing: 14) {
          Text("\(poss)%").font(.system(size: 26, design: Dark.mono)).frame(width: 78, alignment: .leading)
          ShareBar(share: Double(poss) / 100)
          Text("\(100 - poss)%").font(.system(size: 26, design: Dark.mono)).foregroundStyle(Dark.soft)
            .frame(width: 78, alignment: .trailing)
        }
        .padding(.bottom, 14)
      }
      if rows.isEmpty { DarkNote(text: "No stats yet") }
      ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { i, r in
        HStack {
          Text(r.home).font(.system(size: 26, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.ink : Dark.home)
            .frame(width: 96, alignment: .leading)
          Text(r.label).font(.system(size: 18)).foregroundStyle(Dark.dim).frame(maxWidth: .infinity)
          Text(r.away).font(.system(size: 26, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.soft : Dark.away)
            .frame(width: 96, alignment: .trailing)
        }
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(Dark.hair).frame(height: 1) }
        .overlay(alignment: .bottom) { if i == min(rows.count, 5) - 1 { Rectangle().fill(Dark.hair).frame(height: 1) } }
      }
    }
  }
}

/// Other live matches: one row each, score in the middle.
private struct DarkOtherLive: View {
  let lines: [String]

  var body: some View {
    let games = lines.compactMap(DeckFormat.otherLive)
    VStack(alignment: .leading, spacing: 0) {
      DarkHeading(title: "Other live matches", note: games.isEmpty ? nil : "\(games.count) live").padding(.bottom, 10)
      if games.isEmpty {
        ForEach(Array(lines.prefix(4).enumerated()), id: \.offset) { _, l in DarkNote(text: l) }
      }
      ForEach(Array(games.prefix(4).enumerated()), id: \.offset) { i, g in
        HStack(spacing: 14) {
          Circle().fill(Dark.accent).frame(width: 8, height: 8)
          Text(g.home).font(.system(size: 22, weight: .semibold))
          Text(g.homeGoals).font(.system(size: 32, weight: .medium, design: Dark.mono))
          Text("–").font(.system(size: 20, design: Dark.mono)).foregroundStyle(Dark.dim)
          Text(g.awayGoals).font(.system(size: 32, weight: .medium, design: Dark.mono))
          Text(g.away).font(.system(size: 22, weight: .semibold))
          Spacer(minLength: 4)
          if let clock = g.clock {
            Text(clock).font(.system(size: 22, design: Dark.mono)).foregroundStyle(Dark.clock).lineLimit(1)
          }
        }
        .frame(height: 72)
        .overlay(alignment: .top) { Rectangle().fill(Dark.hair).frame(height: 1) }
        .overlay(alignment: .bottom) { if i == min(games.count, 4) - 1 { Rectangle().fill(Dark.hair).frame(height: 1) } }
      }
      Spacer(minLength: 0)
      DarkFooter(left: "Followed leagues only", right: "Swipe up for your match")
    }
  }
}

private struct DarkFooter: View {
  let left: String
  let right: String
  var leftIsAction = false

  var body: some View {
    HStack {
      Text(left).font(.system(size: 17, design: leftIsAction ? .default : Dark.mono))
        .foregroundStyle(leftIsAction ? (Dark.a ? Dark.soft : Color(hex: 0xB9A6FF)) : Dark.dim)
      Spacer(minLength: 8)
      Text(right).font(.system(size: 17)).foregroundStyle(Dark.a ? Dark.soft : Dark.dim)
    }
    .lineLimit(1).minimumScaleFactor(0.7)
    .padding(.top, 14)
    .overlay(alignment: .top) { Rectangle().fill(Dark.hair).frame(height: 1) }
  }
}

private struct DarkStory: View {
  let c: InsightContent

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      DarkHeading(title: sentence(c.title), icon: "sparkles")
      if let question = c.question {
        Text("\u{201C}\(question)\u{201D}").font(.system(size: 21)).foregroundStyle(Dark.soft)
          .lineLimit(2).minimumScaleFactor(0.7)
      }
      if !c.body.isEmpty {
        Text(c.body).font(.system(size: 26)).lineSpacing(6).minimumScaleFactor(0.7)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      DarkFooter(left: c.footer.replacingOccurrences(of: " · ", with: ", "), right: "Pinch and hold to ask")
    }
  }

  private func sentence(_ s: String) -> String {
    s.uppercased() == s ? s.prefix(1) + s.dropFirst().lowercased() : s
  }
}

private struct DarkBoard: View {
  let xi: [LineupPlayer]
  let opponent: [LineupPlayer]?
  let isHome: Bool
  let focus: Int?
  let teamName: String
  let formation: String?

  var body: some View {
    let spots = FormationLayout.spots(xi)
    let focused = focus.flatMap { xi.indices.contains($0) ? xi[$0] : nil }
    let line = Dark.a ? Color(hex: 0x3A3A3E) : Dark.accent.opacity(0.28)
    VStack(spacing: 0) {
      GeometryReader { g in
        let w = g.size.width, h = g.size.height
        ZStack {
          Rectangle().strokeBorder(line, lineWidth: 1)
          PitchLines(westToEast: true).stroke(line, lineWidth: 1)
          ForEach(Array(FormationLayout.spots(opponent ?? []).enumerated()), id: \.offset) { _, spot in
            OpponentMark(number: spot.player.number)
              .position(spot.inHalf(home: !isHome, w, h))
          }
          ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
            let on = spot.player == focused
            VStack(spacing: 3) {
              Text(spot.player.number.map(String.init) ?? "")
                .font(.system(size: 17, weight: .medium, design: Dark.mono))
                .foregroundStyle(on ? .black : Dark.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Dark.accent : .black))
                .overlay(Circle().strokeBorder(on ? Dark.accent : (Dark.a ? Dark.soft : Dark.home.opacity(0.7)), lineWidth: 1))
              Text(Face.surname(spot.player.name))
                .font(.system(size: 15, weight: on ? .bold : .regular))
                .foregroundStyle(on ? Dark.ink : Dark.soft)
                .lineLimit(1).minimumScaleFactor(0.55).frame(width: 74)
            }
            .position(spot.inHalf(home: isHome, w, h))
          }
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        if let focused {
          Text(DarkGlassFormat.displayName(focused.name)).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
          if let n = focused.number { Text("#\(n)").font(.system(size: 18, design: Dark.mono)).foregroundStyle(Dark.soft) }
          if let pos = focused.position.flatMap(PositionLabel.long) { Text(pos).font(.system(size: 18)).foregroundStyle(Dark.dim) }
          Spacer(minLength: 4)
          Text("Pinch for stats").font(.system(size: 17)).foregroundStyle(Dark.a ? Dark.ink : Color(hex: 0xB9A6FF))
        } else {
          Text(teamName).font(.system(size: 24, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
          if let formation {
            Text(formation).font(.system(size: 18, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.dim : Dark.accent)
          }
          Spacer(minLength: 4)
          Text("Pinch for players").font(.system(size: 17)).foregroundStyle(Dark.a ? Dark.soft : Color(hex: 0xB9A6FF))
        }
      }
      .padding(.top, 18)
    }
  }
}

private enum PositionLabel {
  static func short(_ code: String) -> String? {
    switch code.uppercased().first {
    case "G": return "GK"
    case "D": return "DEF"
    case "M": return "MID"
    case "F": return "FWD"
    default: return nil
    }
  }

  static func long(_ code: String) -> String? {
    switch code.uppercased().first {
    case "G": return "Goalkeeper"
    case "D": return "Defence"
    case "M": return "Midfield"
    case "F": return "Forward"
    default: return nil
    }
  }
}

private struct DarkPlayer: View {
  let player: LineupPlayer
  let photo: UIImage?
  let stats: PlayerStats?
  let spot: FormationSpot?
  let heat: [HeatPoint]?
  let scripted: Bool
  let counter: String

  var body: some View {
    let tiles = DarkGlassFormat.keyFigures(position: player.position, stats: stats)
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 10) {
          Text(DarkGlassFormat.displayName(player.name)).font(.system(size: 36, weight: .bold)).tracking(-0.5)
            .lineLimit(1).minimumScaleFactor(0.6)
          HStack(spacing: 12) {
            if let n = player.number { Text("#\(n)").font(.system(size: 17, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.soft : Dark.accent) }
            if let pos = player.position.flatMap(PositionLabel.long) { Text(pos).font(.system(size: 17)).foregroundStyle(Dark.dim) }
            if let m = stats?.minutes { Text("\(m) min").font(.system(size: 17, design: Dark.mono)).foregroundStyle(Dark.soft) }
            if stats?.yellowCards ?? 0 > 0 { RoundedRectangle(cornerRadius: 2).fill(Palette.captain).frame(width: 10, height: 15) }
            if stats?.redCards ?? 0 > 0 { RoundedRectangle(cornerRadius: 2).fill(Palette.coral).frame(width: 10, height: 15) }
            if scripted { Chip(text: "scripted") }
          }
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 6) {
          if let rating = stats?.rating {
            Text(rating).font(.system(size: 46, weight: .medium, design: Dark.mono)).foregroundStyle(Dark.accent)
          }
          Text(stats?.rating == nil ? counterText : "Rating, \(counterText)").font(.system(size: 16)).foregroundStyle(Dark.dim)
        }
      }
      HStack(alignment: .top, spacing: 22) {
        if tiles.isEmpty {
          DarkNote(text: stats == nil ? "No match figures yet" : "Nothing on the scoresheet yet")
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: Dark.a ? 1 : 10), GridItem(.flexible())],
                    spacing: Dark.a ? 1 : 10) {
            ForEach(Array(tiles.prefix(4).enumerated()), id: \.offset) { _, t in tile(t) }
          }
          .background(Dark.a ? Dark.hair : .clear)
          .overlay(Dark.a ? Rectangle().strokeBorder(Dark.hair, lineWidth: 1) : nil)
        }
        if let spot { DeckPitch(spot: spot, heat: heat).frame(width: 200) }
      }
      Spacer(minLength: 0)
      DarkFooter(left: "Pinch to close", right: "Swipe for next player", leftIsAction: true)
    }
  }

  private var counterText: String { counter.replacingOccurrences(of: "/", with: " of ") }

  private func tile(_ t: StatTile) -> some View {
    let parts = t.label.components(separatedBy: " · ")
    let label = parts[0].prefix(1).uppercased() + parts[0].dropFirst().lowercased()
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(t.value).font(.system(size: 32, design: Dark.mono))
        if parts.count > 1 {
          Text(parts[1]).font(.system(size: 15, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.soft : Dark.accent)
        }
      }
      Text(label).font(.system(size: 16)).foregroundStyle(Dark.dim).lineLimit(1).minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 16).padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Dark.a ? AnyShapeStyle(Color.black) : AnyShapeStyle(Color.white.opacity(0.03)),
                in: RoundedRectangle(cornerRadius: Dark.a ? 0 : 12, style: .continuous))
    .overlay(Dark.a ? nil : RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
  }
}

private struct Chip: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 13, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.dim : Dark.soft)
      .padding(.horizontal, 7).padding(.vertical, 2)
      .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Dark.a ? Dark.rule : .white.opacity(0.25), lineWidth: 1))
  }
}

/// The player card's small pitch: where the player lines up, and (demo only)
/// the simulated heat around it, labelled as such.
private struct DeckPitch: View {
  let spot: FormationSpot
  let heat: [HeatPoint]?

  var body: some View {
    let line = Dark.a ? Color(hex: 0x3A3A3E) : Dark.accent.opacity(0.35)
    VStack(spacing: 8) {
      GeometryReader { g in
        let w = g.size.width, h = g.size.height
        ZStack {
          if let heat {
            ForEach(Array(heat.enumerated()), id: \.offset) { _, p in
              Circle()
                .fill(RadialGradient(colors: [Dark.a ? .white.opacity(0.35) : Color(hex: 0xB9A6FF).opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 15))
                .frame(width: 30, height: 30)
                .position(WestToEast.point(x: p.x, y: p.y, w, h))
            }
          }
          Rectangle().strokeBorder(line, lineWidth: 1)
          PitchLines(westToEast: true).stroke(line, lineWidth: 1)
          Circle().fill(Dark.ink).frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(Dark.accent.opacity(0.6), lineWidth: 1).frame(width: 22, height: 22))
            .position(spot.westToEast(w, h))
        }
      }
      .frame(height: 124)
      HStack {
        Text(heat == nil ? "Position" : "Heat").font(.system(size: 15)).foregroundStyle(Dark.dim)
        Spacer()
        if heat != nil { Chip(text: "simulated") }
      }
    }
  }
}

/// Goal banners and other big moments: one calm word, the scorer below.
private struct DeckTakeover: View {
  let t: TakeoverContent
  let score: CompactScore?

  var body: some View {
    let detail = t.detail.map(BannerFormat.detail)
    let title = BannerFormat.title(t.headline)
    let isGoal = title.lowercased().contains("goal") && !title.hasPrefix("VAR")
    ZStack {
      Dark.backdrop
      VStack {
        if let score {
          HStack(spacing: 12) {
            Crest(image: score.homeCrest, fallback: score.summary.homeCode, size: 26)
            Text(score.summary.homeCode).font(.system(size: 19, weight: .semibold)).foregroundStyle(Dark.soft)
            Text("\(score.summary.score.home)").font(.system(size: 28, design: Dark.mono))
            Text("–").font(.system(size: 19, design: Dark.mono)).foregroundStyle(Dark.dim)
            Text("\(score.summary.score.away)").font(.system(size: 28, design: Dark.mono))
            Text(score.summary.awayCode).font(.system(size: 19, weight: .semibold)).foregroundStyle(Dark.soft)
            Crest(image: score.awayCrest, fallback: score.summary.awayCode, size: 26)
          }
        } else {
          Text(t.scoreLine).font(.system(size: 20, design: Dark.mono)).foregroundStyle(Dark.soft)
        }
        Spacer(minLength: 0)
        VStack(spacing: 18) {
          if isGoal {
            Image(systemName: "soccerball").font(.system(size: 50, weight: .ultraLight))
              .frame(width: 72, height: 72)
              .overlay(Dark.a ? nil : Circle().strokeBorder(Dark.accent.opacity(0.6), lineWidth: 1))
              .shadow(color: Dark.a ? .clear : Dark.accent.opacity(0.6), radius: 12)
          }
          Text(title)
            .font(.system(size: 112, weight: .bold)).tracking(-4)
            .lineLimit(1).minimumScaleFactor(0.4)
        }
        Spacer(minLength: 0)
        if let detail {
          VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(detail.who).font(.system(size: 28, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
              if let minute = detail.minute { Text(minute).font(.system(size: 26, design: Dark.mono)).foregroundStyle(Dark.soft) }
            }
            if let rest = detail.rest { Text(rest).font(.system(size: 18)).foregroundStyle(Dark.dim).lineLimit(1) }
          }
        }
      }
      .padding(40)
    }
    .foregroundStyle(Dark.ink)
  }
}

/// Before the first page: the two crests, home and away, and the competition.
private struct DeckIntro: View {
  let i: IntroContent
  let homeCrest: UIImage?
  let awayCrest: UIImage?

  var body: some View {
    ZStack {
      Dark.backdrop
      VStack(spacing: 40) {
        HStack(alignment: .top, spacing: 36) {
          side(i.homeCode, crest: homeCrest, label: "home", tint: Dark.home)
          Text("v").font(.system(size: 22)).foregroundStyle(Dark.dim).padding(.top, 40)
          side(i.awayCode, crest: awayCrest, label: "away", tint: Dark.away)
        }
        if let competition = i.competition {
          let parts = competition.components(separatedBy: " (")
          HStack(spacing: 12) {
            Text(parts[0]).font(.system(size: 18)).foregroundStyle(Dark.soft)
            if parts.count > 1 {
              Rectangle().fill(Dark.rule).frame(width: 1, height: 16)
              Text(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ")")))
                .font(.system(size: 16, design: Dark.mono)).foregroundStyle(Dark.dim)
            }
          }
          .padding(.horizontal, 18).padding(.vertical, 8)
          .overlay(Capsule().strokeBorder(Dark.a ? Dark.rule : .white.opacity(0.14), lineWidth: 1))
        }
      }
    }
    .foregroundStyle(Dark.ink)
  }

  private func side(_ code: String, crest: UIImage?, label: String, tint: Color) -> some View {
    VStack(spacing: 14) {
      Crest(image: crest, fallback: code, size: 64)
        .frame(width: 104, height: 104)
        .background(Circle().fill(.white.opacity(Dark.a ? 0 : 0.04)))
        .overlay(Circle().strokeBorder(Dark.a ? Dark.ink : tint.opacity(0.8), lineWidth: 1))
        .shadow(color: Dark.a ? .clear : tint.opacity(0.4), radius: 10)
      Text(code).font(.system(size: 24, weight: .semibold))
      Text(label).font(.system(size: 16, design: Dark.mono)).foregroundStyle(Dark.a ? Dark.dim : tint)
    }
    .frame(width: 150)
  }
}

/// "Loading the match…" and other one-line messages.
private struct DeckMessage: View {
  let text: String

  var body: some View {
    ZStack {
      Dark.backdrop
      VStack(spacing: 28) {
        Circle().strokeBorder(Dark.a ? Dark.rule : Dark.accent.opacity(0.5), lineWidth: 1)
          .frame(width: 56, height: 56)
          .overlay(Circle().fill(Dark.accent).frame(width: 8, height: 8))
        Text(text.trimmingCharacters(in: CharacterSet(charactersIn: ".…")))
          .font(.system(size: 30, weight: .semibold)).multilineTextAlignment(.center)
          .minimumScaleFactor(0.6).padding(.horizontal, 40)
      }
    }
    .foregroundStyle(Dark.ink)
  }
}

private extension FormationSpot {
  /// The spot on a west-to-east pitch of this size.
  func westToEast(_ width: CGFloat, _ height: CGFloat) -> CGPoint {
    WestToEast.point(x: x, y: y, width, height)
  }

  /// The spot in the team's own half of a west-to-east pitch: home from its
  /// goal on the left up to near halfway, attacking right; away mirrored,
  /// attacking left, with its left flank at the bottom.
  func inHalf(home: Bool, _ width: CGFloat, _ height: CGFloat) -> CGPoint {
    let depth = min(1, max(0, (y - 0.08) / 0.84))     // keeper 0 … forwards 1
    let across = 0.04 + depth * 0.42                    // stops just short of halfway
    return home ? CGPoint(x: across * width, y: x * height)
                : CGPoint(x: (1 - across) * width, y: (1 - x) * height)
  }
}

/// The other team on the formation board: a dim shirt number.
private struct OpponentMark: View {
  let number: Int?

  var body: some View {
    Text(number.map(String.init) ?? "")
      .font(.system(size: 15, weight: .bold)).monospacedDigit()
      .foregroundStyle(.white.opacity(0.5))
      .frame(width: 28, height: 28)
      .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.2))
  }
}

/// The upright layout (keeper at the top, col 1 = the team's left on the
/// left) laid west to east: depth runs left to right, and a team attacking
/// to the right has its left flank at the top.
private enum WestToEast {
  static func point(x: Double, y: Double, _ width: CGFloat, _ height: CGFloat) -> CGPoint {
    CGPoint(x: y * width, y: x * height)
  }
}
