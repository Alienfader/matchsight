import SwiftUI

struct ErrorBanner: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.white)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
      SwiftUI.Button(action: onDismiss) {
        Image(systemName: "xmark")
          .foregroundStyle(.white.opacity(0.85))
      }
      .buttonStyle(.plain)
    }
    .padding(14)
    .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
    .padding(.horizontal, 16)
  }
}
