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

  @MainActor static func scorePanel(_ p: PanelContent, toast: String?,
                                    homeCrest: UIImage?, awayCrest: UIImage?) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      if p.isPreMatch {
        PreMatchCapsule(p: p, homeCrest: homeCrest, awayCrest: awayCrest)
      } else {
        LiveScoreCapsule(p: p, homeCrest: homeCrest, awayCrest: awayCrest)
      }
    })
  }

  @MainActor static func carousel(xi: [LineupPlayer], index: Int, teamLine: String,
                                  counter: String, toast: String?,
                                  photos: @escaping (Int) -> UIImage?, stats: [Int: PlayerStats]) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      PlayerCardStack(xi: xi, index: index, teamLine: teamLine, counter: counter,
                      photos: photos, stats: stats)
    })
  }

  @MainActor static func insight(_ c: InsightContent, toast: String?, score: CompactScore?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { InsightPage(c: c) })
  }

  /// Events, Stats and Other Live: a titled list of pre-formatted lines.
  @MainActor static func list(title: String, lines: [String], toast: String?, score: CompactScore?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { ListPage(title: title, lines: lines) })
  }

  /// The STARTING XI board (first card of a lineup page): the formation when
  /// the XI is known, else the text rows ("lineup not available").
  @MainActor static func roster(_ c: LineupContent, xi: [LineupPlayer]?, crest: UIImage?,
                                photos: @escaping (Int) -> UIImage?, stats: [Int: PlayerStats],
                                toast: String?) -> UIImage? {
    render(PageFrame(toast: toast, score: nil) {
      FormationBoard(c: c, xi: xi, crest: crest, photos: photos, stats: stats)
    })
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

  @MainActor static func message(_ text: String, toast: String?, score: CompactScore?) -> UIImage? {
    render(PageFrame(toast: toast, score: score) { MessagePage(text: text) })
  }

  @MainActor private static func render(_ view: some View) -> UIImage? {
    let r = ImageRenderer(content: view.frame(width: 600, height: 600).background(.black))
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

/// Two-section capsule: a bright pill on top, a frostier smoky band below.
private struct TwoSectionCapsule<Top: View, Lower: View>: View {
  @ViewBuilder let top: () -> Top
  @ViewBuilder let lower: () -> Lower

  var body: some View {
    VStack(spacing: 0) {
      top()
        .frame(maxWidth: .infinity).frame(height: 132)
        .background(Glass(tint: .signature, radius: 56, opacity: 0.55))
        .overlay(alignment: .topLeading) { Streaks().clipShape(Capsule()) }
      lower()
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 26)
        .background(Glass(tint: .smoky, radius: 30, opacity: 0.4).padding(.horizontal, 22))
        .padding(.top, -6)
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
          Capsule().fill(Palette.probabilityCyan).frame(width: g.size.width * CGFloat(p.home) / total)
          if p.draw > 0 {
            Capsule().fill(Palette.softPurple).frame(width: g.size.width * CGFloat(p.draw) / total)
          }
          Capsule().fill(Palette.coral)
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
          Capsule().fill(Palette.probabilityCyan).frame(width: g.size.width * CGFloat(home) / 100)
          Capsule().fill(Palette.coral)
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

// MARK: - Starting XI: formation board

private struct FormationBoard: View {
  let c: LineupContent
  let xi: [LineupPlayer]?
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
        LinePitch(spots: FormationLayout.spots(xi), photos: photos, stats: stats)
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

/// Line-art pitch over the glass, keeper at the top, each starter as a small
/// headshot with number and surname.
private struct LinePitch: View {
  let spots: [FormationSpot]
  let photos: (Int) -> UIImage?
  let stats: [Int: PlayerStats]

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      ZStack {
        PitchLines().stroke(.white.opacity(0.45), lineWidth: 1.5)
        ForEach(Array(spots.enumerated()), id: \.offset) { _, spot in
          FormationPlayer(player: spot.player,
                          photo: spot.player.playerId.flatMap(photos),
                          isCaptain: spot.player.playerId.flatMap { stats[$0] }?.isCaptain == true)
            .position(x: spot.x * w, y: spot.y * h)
        }
      }
    }
  }
}

/// Full pitch geometry: outline, halfway line, centre circle, both boxes.
private struct PitchLines: Shape {
  func path(in r: CGRect) -> Path {
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
        .frame(width: 46, height: 46)
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
      Text(Face.surname(player.name))
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1).minimumScaleFactor(0.6)
        .frame(width: 92)
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
      CardTitle(icon: "sparkles", title: c.title)
      // Bodies are ≤ 150 characters (MatchInsight.maxBody): about six
      // lines at 34 pt, so the shrink is only a safety margin.
      Text(c.body)
        .font(.system(size: 34, weight: .medium))
        .lineSpacing(2).minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: true)
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
