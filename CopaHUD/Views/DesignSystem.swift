import SwiftUI
import CopaHUDCore

// MARK: - Flag Lookup (phone-side chrome; glasses HUD uses NationStyle)

func flagEmoji(for teamName: String) -> String {
  let flags: [String: String] = [
    "brazil": "🇧🇷", "argentina": "🇦🇷", "france": "🇫🇷", "germany": "🇩🇪",
    "spain": "🇪🇸", "england": "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "portugal": "🇵🇹", "netherlands": "🇳🇱",
    "croatia": "🇭🇷", "japan": "🇯🇵", "south korea": "🇰🇷", "mexico": "🇲🇽",
    "usa": "🇺🇸", "united states": "🇺🇸", "switzerland": "🇨🇭", "belgium": "🇧🇪",
    "italy": "🇮🇹", "uruguay": "🇺🇾", "colombia": "🇨🇴", "morocco": "🇲🇦",
    "senegal": "🇸🇳", "canada": "🇨🇦", "australia": "🇦🇺", "poland": "🇵🇱",
  ]
  return flags[teamName.lowercased()] ?? "🏳️"
}

// MARK: - Color Tokens

extension Color {
  // Navy surfaces (darkest → lightest)
  static let navy900 = Color(red: 0.020, green: 0.078, blue: 0.220)
  static let navy800 = Color(red: 0.039, green: 0.059, blue: 0.122)
  static let navy700 = Color(red: 0.059, green: 0.122, blue: 0.302)
  static let navy600 = Color(red: 0.078, green: 0.141, blue: 0.349)
  static let navy500 = Color(red: 0.102, green: 0.149, blue: 0.302)
  static let navy400 = Color(red: 0.122, green: 0.200, blue: 0.451)

  // Broadcast accents
  static let goal    = Color(red: 1.000, green: 0.851, blue: 0.102) // #FFD91A
  static let goalDeep = Color(red: 1.000, green: 0.651, blue: 0.102) // #FFA61A half-time amber
  static let live    = Color(red: 0.302, green: 1.000, blue: 0.502) // #4DFF80
  static let cyan    = Color(red: 0.400, green: 0.851, blue: 1.000) // #66D9FF
  static let alertRed = Color(red: 1.000, green: 0.302, blue: 0.302) // #FF4D4D
  static let actionBlue = Color(red: 0.149, green: 0.502, blue: 1.000) // #2680FF
}

// MARK: - App Gradient

extension LinearGradient {
  static let appBackground = LinearGradient(
    colors: [Color(red: 0.031, green: 0.078, blue: 0.220), Color(red: 0.078, green: 0.141, blue: 0.349)],
    startPoint: .top, endPoint: .bottom
  )
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
  enum Variant { case `default`, strong, followed, live }
  let variant: Variant
  let radius: CGFloat
  let content: () -> Content

  init(variant: Variant = .default, radius: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
    self.variant = variant
    self.radius = radius
    self.content = content
  }

  var body: some View {
    content()
      .background(fillColor, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(strokeColor, lineWidth: 1))
  }

  private var fillColor: Color {
    switch variant {
    case .default:  return .white.opacity(0.05)
    case .strong:   return .white.opacity(0.10)
    case .followed: return Color(red: 0.851, green: 0.102, blue: 0.102).opacity(0.16)
    case .live:     return Color(red: 0.851, green: 0.102, blue: 0.102).opacity(0.12)
    }
  }

  private var strokeColor: Color {
    switch variant {
    case .default:  return .white.opacity(0.10)
    case .strong:   return .white.opacity(0.12)
    case .followed: return Color.yellow.opacity(0.45)
    case .live:     return Color.alertRed.opacity(0.35)
    }
  }
}

// MARK: - CrestView

struct CrestView: View {
  let team: String
  var size: CGFloat = 30

  var body: some View {
    ZStack {
      Circle()
        .fill(RadialGradient(
          colors: [Color.navy500, Color.navy700],
          center: .init(x: 0.3, y: 0.2),
          startRadius: 0,
          endRadius: size
        ))
        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
      Text(flagEmoji(for: team))
        .font(.system(size: size * 0.56))
    }
    .frame(width: size, height: size)
  }
}

// MARK: - TeamBadge (club crest, nation flag fallback)

/// A club's real crest when the feed has one; otherwise the existing
/// flag-in-a-circle (nations) or the club code (unknown clubs).
struct TeamBadge: View {
  let team: Team
  var size: CGFloat = 30

  var body: some View {
    if let url = team.logoURL {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFit()
        } else {
          fallback
        }
      }
      .frame(width: size, height: size)
    } else {
      fallback
    }
  }

  @ViewBuilder private var fallback: some View {
    let style = TeamStyle.style(for: team)
    if style.flag.isEmpty {
      Circle()
        .fill(Color.navy500)
        .overlay(Text(style.code).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white))
        .frame(width: size, height: size)
    } else {
      CrestView(team: team.name, size: size)
    }
  }
}

// MARK: - LivePill

struct LivePill: View {
  let status: MatchStatus
  let minute: Int?

  var body: some View {
    HStack(spacing: 6) {
      if showsDot { Circle().fill(pillColor).frame(width: 6, height: 6) }
      Text(pillText)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(pillColor)
        .monospacedDigit()
        .tracking(0.4)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(pillColor.opacity(0.12), in: Capsule())
    .overlay(Capsule().stroke(pillColor.opacity(0.20), lineWidth: 1))
  }

  private var isHT: Bool { status == .halfTime }
  private var isFT: Bool { status.isFinished }
  /// Only live, ticking states get the pulsing dot — HT/FT are static.
  private var showsDot: Bool { !isHT && !isFT }

  private var pillText: String {
    if isHT { return "HT" }
    if isFT { return "FT" }
    return minute.map { "\($0)'" } ?? "LIVE"
  }

  // Design StatusPill: live green · HT amber · FT dim grey.
  private var pillColor: Color {
    if isHT { return .goalDeep }
    if isFT { return .white.opacity(0.55) }
    return .live
  }
}

// MARK: - GradientPossBar (phone-side rich bar)

struct GradientPossBar: View {
  let home: Int

  var body: some View {
    VStack(spacing: 7) {
      GeometryReader { geo in
        HStack(spacing: 0) {
          LinearGradient(colors: [.cyan, .actionBlue], startPoint: .leading, endPoint: .trailing)
            .frame(width: geo.size.width * CGFloat(home) / 100)
          Color.white.opacity(0.18)
        }
        .clipShape(Capsule())
      }
      .frame(height: 6)
      HStack {
        Text("POSS \(home)%")
        Spacer()
        Text("\(100 - home)%")
      }
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white.opacity(0.55))
      .tracking(0.4)
    }
  }
}

// MARK: - SectionHeader

struct SectionHeader: View {
  let title: String
  var count: Int? = nil
  var isLive: Bool = false

  var body: some View {
    HStack(spacing: 8) {
      if isLive {
        Circle().fill(Color.alertRed)
          .frame(width: 7, height: 7)
          .shadow(color: .alertRed, radius: 4)
      }
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(isLive ? Color.alertRed : Color.white.opacity(0.70))
        .tracking(0.4)
        .textCase(.uppercase)
      if let n = count {
        Text("\(n)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.45))
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(Capsule().fill(Color.white.opacity(0.08)))
      }
      LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
        .frame(height: 1)
    }
  }
}
