import MWDATCore
import SwiftUI

struct PairingView: View {
  @Bindable var glasses: GlassesViewModel

  var body: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.08, blue: 0.22),
          Color(red: 0.08, green: 0.14, blue: 0.35)
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 28) {
          heroSection
          glassesCard
          if glasses.requiresDATAppUpdate {
            datUpdateCard
          }
          footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
      }
    }
  }

  // MARK: - Hero

  private var heroSection: some View {
    VStack(spacing: 14) {
      Text("⚽")
        .font(.system(size: 72))
        .frame(width: 96, height: 96)
        .background(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [.green, Color(red: 0.0, green: 0.45, blue: 0.85)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
        .overlay(
          RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )

      VStack(spacing: 6) {
        Text("Matchsight")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
        Text("Your team's live match on your glasses. Goals take over the HUD; the Neural Band flips the deck.")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.white.opacity(0.65))
          .multilineTextAlignment(.center)
      }
    }
    .padding(.top, 12)
    .padding(.bottom, 4)
  }

  // MARK: - Glasses card

  private var glassesCard: some View {
    Card {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          ZStack {
            Circle()
              .fill(glassesIconBackground)
              .frame(width: 44, height: 44)
            Image(systemName: "eyeglasses")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(.white)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text("Display Glasses")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white)
            statusBadge
          }
          Spacer()
        }

        primaryGlassesAction
      }
    }
  }

  @ViewBuilder
  private var primaryGlassesAction: some View {
    switch glasses.registrationState {
    case .registered:
      HStack(spacing: 12) {
        SwiftUI.Button {
          Task { await glasses.startUnregistration() }
        } label: {
          Label("Unpair", systemImage: "trash")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
      }
    case .available, .unavailable:
      SwiftUI.Button {
        Task { await glasses.startRegistration() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "link")
          Text("Pair Glasses")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
          LinearGradient(
            colors: [.blue, Color(red: 0.25, green: 0.45, blue: 0.95)],
            startPoint: .leading,
            endPoint: .trailing
          ),
          in: Capsule()
        )
        .shadow(color: .blue.opacity(0.35), radius: 12, x: 0, y: 6)
      }
      .buttonStyle(.plain)
    case .registering:
      HStack(spacing: 10) {
        ProgressView().tint(.white)
        Text("Connecting to Meta AI…")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.white.opacity(0.8))
      }
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      .background(Color.white.opacity(0.06), in: Capsule())
    @unknown default:
      EmptyView()
    }
  }

  private var statusBadge: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(statusColor)
        .frame(width: 7, height: 7)
        .shadow(color: statusColor.opacity(0.7), radius: 4)
      Text(statusText)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
    }
  }

  private var statusText: String {
    switch glasses.registrationState {
    case .registered: "Connected to Meta AI"
    case .registering: "Connecting…"
    case .available: "Ready to pair"
    case .unavailable: "Meta AI unavailable"
    @unknown default: "Unknown state"
    }
  }

  private var statusColor: Color {
    switch glasses.registrationState {
    case .registered: .green
    case .registering: .orange
    case .available: .yellow
    case .unavailable: .red
    @unknown default: .gray
    }
  }

  private var glassesIconBackground: LinearGradient {
    LinearGradient(
      colors: glasses.registrationState == .registered
        ? [.green, Color(red: 0.0, green: 0.55, blue: 0.4)]
        : [Color.blue.opacity(0.7), Color.indigo.opacity(0.7)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  // MARK: - DAT update prompt

  private var datUpdateCard: some View {
    Card(tint: .yellow) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(.yellow)
          Text("Glasses Need Update")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
          Spacer()
        }
        Text("The Meta AI app needs to update the DAT runtime on your glasses before we can connect.")
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.7))
          .fixedSize(horizontal: false, vertical: true)
        SwiftUI.Button {
          Task { await glasses.openDATAppUpdate() }
        } label: {
          Text("Open Meta AI to Update")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.yellow, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  // MARK: - Footer

  private var footer: some View {
    VStack(spacing: 4) {
      Text("Matchsight · v1")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
      Text("by alienfader")
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.25))
    }
    .padding(.top, 20)
  }
}

// MARK: - Reusable card chrome

struct Card<Content: View>: View {
  let tint: Color?
  let content: () -> Content

  init(tint: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
    self.tint = tint
    self.content = content
  }

  var body: some View {
    content()
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color.white.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(
            tint?.opacity(0.35) ?? Color.white.opacity(0.1),
            lineWidth: 1
          )
      )
      .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
  }
}
