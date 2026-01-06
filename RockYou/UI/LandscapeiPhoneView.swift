//
//  LandscapeiPhoneView.swift
//  RockYou
//
//  Landscape iPhone layout: Left 2x3 grid, D-Pad center, Right 2x3 grid

import SwiftUI

struct LandscapeiPhoneView: View {
  let onAction: (RemoteAction) -> Void
  let onKeyboard: () -> Void
  let isKeyboardShown: Bool
  @Binding var showingConfigure: Bool
  @Binding var showingTVSelector: Bool
  let selectedTVName: String?
  let selectedStreamerName: String?
  let selectedDeviceId: String?
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
    let topPad: CGFloat = 8 * s
    let headerBottomPad: CGFloat = 8 * s

    VStack(spacing: 0) {
      landscapeAlignedHeader(scaleFactor: s)
        .padding(.top, topPad)
        .padding(.bottom, headerBottomPad)
        .background(Color.black.opacity(AppOpacity.standard))

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

          Spacer().frame(width: 34 * s)

          rightButtonGrid(scaleFactor: s)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.top, 14 * s)
      .padding(.bottom, 12 * s)
    }
  }

  // MARK: - Landscape header: align buttons to grid columns

  private static let helpMaterialSeed: UInt64 = 0xC0FFEE

  private func landscapeAlignedHeader(scaleFactor s: CGFloat) -> some View {
    // These match the grid geometry below.
    let topKeyW: CGFloat = 68 * s
    let topKeyH: CGFloat = 52 * s
    let leftGridSpacing: CGFloat = 24 * s
    let dPadSize: CGFloat = 190 * s
    let dPadToRightSpacer: CGFloat = 34 * s
    let transportColW: CGFloat = 76 * s
    let rightGridSpacing: CGFloat = 24 * s

    let leftGridW: CGFloat = topKeyW * 2 + leftGridSpacing
    let rightGridW: CGFloat = transportColW + rightGridSpacing + topKeyW
    let groupW: CGFloat = leftGridW + dPadSize + dPadToRightSpacer + rightGridW

    return ZStack {
      // Selector bar should be centered between help/power and match the control group's width.
      TVSelectorBar(
        selectedTVName: selectedTVName,
        selectedStreamerName: selectedStreamerName,
        selectedDeviceId: selectedDeviceId,
        showingSelector: showingTVSelector,
        onTap: {
          withAnimation(.easeInOut(duration: 0.2)) {
            showingTVSelector.toggle()
          }
        }
      )
      .frame(width: groupW)

      // Column-aligned button overlay:
      // - Help centered over left column 1 (Back/Home/Settings)
      // - Power centered over right column 2 (Volume column)
      HStack(spacing: 0) {
        Spacer()

        HStack(spacing: 0) {
          // Left grid: two columns
          HStack(spacing: leftGridSpacing) {
            Button {
              onKeyboard()
            } label: {
              Image(systemName: isKeyboardShown ? "keyboard.chevron.compact.down" : "keyboard")
                .font(.system(size: AppFontSize.veryLarge, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: topKeyW, height: topKeyH)
            }
            .buttonStyle(
              MaterialButtonEffect.CapsuleStyle(baseColor: rokuPurple, seed: Self.helpMaterialSeed)
            )

            // Keep the second column reserved so the selector remains centered.
            Spacer().frame(width: topKeyW, height: topKeyH)
          }
          .frame(width: leftGridW, alignment: .leading)

          // DPad block + spacer to right grid (no buttons in header here).
          Spacer().frame(width: dPadSize + dPadToRightSpacer)

          // Right grid: transport col + volume col
          HStack(spacing: rightGridSpacing) {
            Spacer().frame(width: transportColW, height: topKeyH)

            SafePowerButton(
              onPower: { onAction(.power) },
              style: .custom(height: topKeyH, showLabel: false),
              safetyDelay: settings.phonePowerDelay
            )
            .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
            .frame(width: topKeyW, height: topKeyH)
          }
          .frame(width: rightGridW, alignment: .trailing)
        }
        .frame(width: groupW)

        Spacer()
      }
    }
  }

  // MARK: - Left Button Grid (Top 5 buttons)

  private func leftButtonGrid(scaleFactor s: CGFloat) -> some View {
    HStack(spacing: 24 * s) {
      // Column 1: Back, Home, Settings
      VStack(spacing: 46 * s) {
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
      VStack(spacing: 46 * s) {
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
    HStack(spacing: 24 * s) {
      // Column 1: Transport controls (Rewind, Play/Pause, Forward)
      VStack(spacing: 30 * s) {
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
      VStack(spacing: 46 * s) {
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
