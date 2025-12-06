import SwiftUI

/// Shared now-playing progress UI (remaining/live above a progress bar).
///
/// This is used in multiple layouts:
/// - `.compactHeader`: sits above the horizontal app strip (tight padding, reserved height).
/// - `.fullPanel`: used inside the Now Playing panel (slightly taller bar, optional endpoints row).
struct NowPlayingProgressView: View {
  @Environment(\.displayScale) private var displayScale

  enum Style: Sendable {
    case compactHeader
    case fullPanel
  }

  let state: DeviceState
  let style: Style

  var body: some View {
    let isLive = state.isLive == true
    let isLiveBlocked = state.isLiveBlocked == true

    let hasProgress =
      (state.mediaPosition != nil && state.mediaDuration != nil && (state.mediaDuration ?? 0) > 0)

    // Style knobs (the only behavioral differences should live here).
    let showTimestamps: Bool = (style == .fullPanel)
    let barHeight: CGFloat = (style == .compactHeader) ? 3 : 4
    let horizontalPadding: CGFloat = (style == .compactHeader) ? 6 : 0
    let reserveTopLineSpace: Bool = (style == .compactHeader)
    let topLineOffsetY: CGFloat = (style == .compactHeader) ? -2 : 0
    let barOffsetY: CGFloat = (style == .compactHeader) ? 1 : 0

    let topLineShouldShow: Bool = showTimestamps ? hasProgress : (isLive || hasProgress)
    let centerFont: Font =
      showTimestamps
      ? .system(.callout, design: .monospaced).weight(.semibold)
      : .system(.caption, design: .monospaced).weight(.semibold)
    let centerColor: Color =
      showTimestamps ? .white.opacity(AppOpacity.primary) : .white

    VStack(spacing: 0) {
      // Adornments (above the line): optional timestamps (full panel), plus center content.
      HStack {
        if showTimestamps,
          let position = state.mediaPosition
        {
          Text(formatTime(milliseconds: position))
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)
        }

        Spacer()

      Group {
        if isLive {
          LiveBadgeView(isBlocked: isLiveBlocked)
          } else if let position = state.mediaPosition,
            let duration = state.mediaDuration,
          duration > 0
        {
          let remaining = max(duration - position, 0)
          Text("\(formatTime(milliseconds: remaining))")
              .font(centerFont)
              .foregroundStyle(centerColor)
          } else if reserveTopLineSpace && !showTimestamps {
          // Placeholder to reserve height when hiding the header.
          Text("00:00")
              .font(centerFont)
              .foregroundStyle(centerColor)
          }
        }

        Spacer()

        if showTimestamps,
          let duration = state.mediaDuration
        {
          Text(formatTime(milliseconds: duration))
            .font(.subheadline.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      // Match the previous below-the-bar spacing (full panel): it used to be padding(.top, 4).
      // Now it lives above the bar, so we use padding(.bottom, 4).
      .padding(.bottom, showTimestamps ? 4 : 0)
      .opacity(topLineShouldShow ? 1 : 0)
      .offset(y: topLineOffsetY)

      // Progress bar (track + fill)
      Group {
        if let position = state.mediaPosition, let duration = state.mediaDuration, duration > 0 {
          GeometryReader { geometry in
            let totalWidth = geometry.size.width
            // Pixel-quantize to avoid last-pixel wobble near 100% (90% fix, tiny code).
            let progress = min(max(CGFloat(position) / CGFloat(duration), 0), 1)
            let fillWidth =
              progress >= 1
              ? totalWidth
              : ((totalWidth * progress * displayScale).rounded(.down) / displayScale)
            ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(AppOpacity.medium))
                .frame(height: barHeight)

              RoundedRectangle(cornerRadius: 2)
                .fill(state.mediaState.color)
                .frame(
                  width: fillWidth,
                  height: barHeight
                )
            }
          }
        } else {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(AppOpacity.medium))
        }
      }
      .frame(height: barHeight)
      .opacity(hasProgress ? 1 : 0)
      .offset(y: barOffsetY)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, horizontalPadding)
    .opacity(AppOpacity.primary)
    .allowsHitTesting(false)
  }

  private func formatTime(milliseconds: Int) -> String {
    let totalSeconds = milliseconds / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

/// Compact now-playing progress header intended to sit above the horizontal app strip.
struct NowPlayingProgressHeaderView: View {
  let deviceId: String

  var body: some View {
    let stateManager = DeviceStateManager.shared
    let state = stateManager.states[deviceId] ?? DeviceState()
    NowPlayingProgressView(state: state, style: .compactHeader)
  }
}
