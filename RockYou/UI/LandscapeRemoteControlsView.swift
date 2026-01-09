import SwiftUI

/// Landscape controls-only surface for iPhone landscape compact layouts.
///
/// The header is owned by the slot-based shell, not this view.
struct LandscapeRemoteControlsView: View {
  let onAction: (RemoteAction) -> Void
  @Binding var showingConfigure: Bool
  let hardwareControlsAvailable: Bool

  @State private var settings = AppSettings.shared
  @State private var naturalSize: CGSize = .zero

  private struct NaturalSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
      let next = nextValue()
      if next != .zero { value = next }
    }
  }

  var body: some View {
    GeometryReader { proxy in
      let available = proxy.size
      let natural = naturalSize
      let scaleW: CGFloat = (natural.width > 0) ? (available.width / natural.width) : 1.0
      let scaleH: CGFloat = (natural.height > 0) ? (available.height / natural.height) : 1.0
      let fitScale: CGFloat = max(0.01, min(1.0, min(scaleW, scaleH)))

      content(scaleFactor: fitScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Report the chosen fit scale up to the shell so the header buttons can match.
        .preference(key: RemoteControlView.ControlsScalePreferenceKey.self, value: fitScale)
        // Report the natural (unscaled) size so the shell can reason about height constraints
        // (e.g. AppStrip lane policy with hysteresis during macOS window resizing).
        .preference(key: RemoteControlView.ControlsNaturalSizePreferenceKey.self, value: naturalSize)
        // Baseline size probe at scale=1.0.
        .background(
          content(scaleFactor: 1.0)
            .background(
              GeometryReader { inner in
                Color.clear.preference(key: NaturalSizePreferenceKey.self, value: inner.size)
              }
            )
            .hidden()
        )
        .onPreferenceChange(NaturalSizePreferenceKey.self) { s in
          if s != .zero, s != naturalSize { naturalSize = s }
        }
    }
  }

  @ViewBuilder
  private func content(scaleFactor s: CGFloat) -> some View {
    let dpadSpacer: CGFloat = 34 * s
    HStack(spacing: 0) {
      // Button section
      HStack {
        leftButtonGrid(scaleFactor: s)

        DPadView(
          onDirection: { onAction($0) },
          onOK: { onAction(.ok) },
          size: 190 * s
        )
        .offset(y: -4 * s)

        Spacer().frame(width: dpadSpacer)

        rightButtonGrid(scaleFactor: s)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.top, 14 * s)
    .padding(.bottom, 12 * s)
  }

  // MARK: - Left Button Grid (Top 5 buttons)

  private func leftButtonGrid(scaleFactor s: CGFloat) -> some View {
    let colGap: CGFloat = 24 * s
    let rowGap: CGFloat = 46 * s
    return HStack(spacing: colGap) {
      // Column 1: Back, Home, Settings
      VStack(spacing: rowGap) {
        TopKeyButton(systemName: "chevron.left", width: 68 * s, height: 52 * s) {
          onAction(.back)
        }
        TopKeyButton(systemName: "house.fill", width: 68 * s, height: 52 * s) {}
          .sweepable(
            icon: "house.fill",
            color: .indigo,
            delay: settings.phoneHomeDelay ?? 0,
            tooltip: "Hold to go home",
            onSweepComplete: { onAction(.home) }
          )
        TopKeyButton(systemName: "gearshape.fill", width: 68 * s, height: 52 * s) {
          showingConfigure = true
        }
      }

      // Column 2: Options, spacer frame, Instant Replay
      VStack(spacing: rowGap) {
        TopKeyButton(
          systemName: "asterisk", width: 68 * s, height: 52 * s, baseColor: rokuDarkPurple
        ) {
          onAction(.options)
        }
        // Spacer frame between Options and Instant Replay
        Spacer().frame(height: 52 * s)
        TopKeyButton(
          systemName: "gobackward.15", width: 68 * s, height: 52 * s, baseColor: rokuDarkPurple
        )
        {
          onAction(.instantReplay)
        }
      }
    }
  }

  // MARK: - Right Button Grid (Bottom 6 buttons)

  private func rightButtonGrid(scaleFactor s: CGFloat) -> some View {
    let colGap: CGFloat = 24 * s
    let rowGap: CGFloat = 46 * s
    let transportRowGap: CGFloat = 30 * s
    return HStack(spacing: colGap) {
      // Column 1: Transport controls (Rewind, Play/Pause, Forward)
      VStack(spacing: transportRowGap) {
        CircleKeyButton(systemName: "backward.fill", size: 68 * s, baseColor: rokuDarkPurple) {
          onAction(.rewind)
        }
        CircleKeyButton(systemName: "playpause.fill", size: 76 * s, baseColor: rokuDarkPurple) {
          onAction(.playPause)
        }
        CircleKeyButton(systemName: "forward.fill", size: 68 * s, baseColor: rokuDarkPurple) {
          onAction(.forward)
        }
      }

      // Column 2: Volume controls (Up, Down, Mute)
      VStack(spacing: rowGap) {
        TopKeyButton(systemName: "speaker.plus.fill", width: 68 * s, height: 52 * s) {
          onAction(.volumeUp)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        TopKeyButton(systemName: "speaker.minus.fill", width: 68 * s, height: 52 * s) {
          onAction(.volumeDown)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        TopKeyButton(systemName: "speaker.slash.fill", width: 68 * s, height: 52 * s) {
          onAction(.volumeMute)
        }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      }
    }
  }
}
