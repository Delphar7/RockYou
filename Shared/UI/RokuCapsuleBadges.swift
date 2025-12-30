//
//  RokuCapsuleBadges.swift
//  RockYou (Shared)
//
//  Shared capsule badge components used across Settings and main UI.
//

import SwiftUI

/// Standard purple capsule label used for paired-device pills.
/// Optionally includes a streaming-device power icon on the leading edge.
struct RokuPurpleCapsuleLabel: View {
  let text: String
  var showStreamerPowerIcon: Bool = false
  var streamerPowerMode: PowerMode = .unknown

  /// Scales the capsule (padding/background) independently of the badge content.
  /// This lets us keep the pill shape reasonable while making the badge itself more legible.
  /// Horizontal-only scaling (widen without increasing height).
  var capsuleScaleX: CGFloat = 1.10

  /// Scales the leading streamer badge icon only (including its internal glyph/text).
  /// The capsule label text is intentionally NOT scaled.
  var badgeIconScale: CGFloat = 1.25
  var badgeIconBaseSize: CGFloat = 12

  // Padding defaults match existing usages.
  var leadingPadding: CGFloat = 8
  var trailingPadding: CGFloat = 8
  var verticalPadding: CGFloat = 4

  var body: some View {
    HStack(spacing: 3) {
      if showStreamerPowerIcon {
        StreamingDeviceIcon(size: badgeIconBaseSize * badgeIconScale, bodyColor: streamerPowerMode.statusColor)
      }
      Text(text)
        .foregroundStyle(.white)
    }
    .rokuPurpleCapsuleBadge(
      leading: leadingPadding * capsuleScaleX,
      trailing: trailingPadding * capsuleScaleX,
      vertical: verticalPadding
    )
  }
}
