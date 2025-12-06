import SwiftUI

struct LiveBadgeView: View {
  let isBlocked: Bool

  var body: some View {
    let color: Color = isBlocked ? .yellow : .green

    HStack(spacing: 4) {
      Image(systemName: "dot.radiowaves.left.and.right")
      Text("LIVE")
    }
    .font(.caption2.weight(.semibold))
    .padding(.horizontal, 6)
    // Slightly shorter capsule (requested: 1pt smaller height)
    .padding(.vertical, 1.5)
    .foregroundStyle(color)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(color.opacity(0.1))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(color.opacity(0.85), lineWidth: 1)
    )
    .overlay {
      if isBlocked {
        Rectangle()
          .fill(color.opacity(0.9))
          .frame(height: 1.5)
          .rotationEffect(.degrees(-20))
          .padding(.horizontal, 4)
      }
    }
    // Nudge the badge up slightly (requested)
    .offset(y: -1)
    .accessibilityLabel(isBlocked ? "Live (blocked)" : "Live")
  }
}
