//
//  MediaPage.swift
//  RockYou Watch App
//

import SwiftUI
import WatchKit

struct MediaPage: View {
  let pageCount: Int
  let currentPage: Int
  let hardwareControlsAvailable: Bool
  let onAction: (RemoteAction) -> Void
  let onCrownChange: (Double, Double) -> Void
  let onSwipeLeft: () -> Void
  let onSwipeRight: () -> Void
  let onPageTap: (Int) -> Void

  @State private var crownValue: Double = 50
  @State private var settings = WatchAppSettings.shared

  // Tiny layout nudges to improve visual alignment on watch:
  // - D-pad slightly higher so it doesn't crowd the bottom row.
  // - Circle buttons slightly higher to align better with the D-pad top edge.
  // - Bottom row slightly lower without moving the page indicator.
  private let dPadYOffset: CGFloat = 8
  private let circleRowTopPadding: CGFloat = 0

  var body: some View {
    VStack(spacing: 4) {
      // Top row: Back, Mute, Power
      topRow

      Spacer(minLength: 0).frame(height: 8)

      // D-Pad with circle buttons at sides, aligned to top
      ZStack(alignment: .top) {
        DPadView(onDirection: { onAction($0) }, onOK: { onAction(.ok) }, size: 80)
          .offset(y: dPadYOffset)

        HStack {
          circleButton(icon: "asterisk", action: .options)
          Spacer()
          circleButton(icon: "gobackward.15", action: .instantReplay)
        }
        .padding(.top, circleRowTopPadding)
        .padding(.horizontal, 2)
      }

      Spacer(minLength: 0).frame(height: 26)

      // Bottom row: Rewind, Play/Pause, Forward
      bottomRow

      PageIndicator(pageCount: pageCount, currentPage: currentPage, onPageTap: onPageTap)
        .padding(.bottom, 2).padding(.top, 6)
    }
    .padding(.horizontal, 8)
    .padding(.top, 4)
    .contentShape(Rectangle())
    .focusable()
    .digitalCrownRotation($crownValue, from: 0, through: 100, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
    .digitalCrownAccessory(.hidden)
    .onChange(of: crownValue) { oldValue, newValue in
      onCrownChange(oldValue, newValue)
    }
    .gesture(
      DragGesture(minimumDistance: 50)
        .onEnded { value in
          let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
          guard isHorizontal else { return }
          if value.translation.width < -50 { onSwipeLeft() }
          if value.translation.width > 50 { onSwipeRight() }
        }
    )
  }

  private var topRow: some View {
    HStack(spacing: 12) {
      RemoteButton("chevron.left") { onAction(.back) }
      RemoteButton("speaker.slash.fill") { onAction(.volumeMute) }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      SafePowerButton(onPower: { onAction(.power) }, safetyDelay: settings.watchPowerDelay)
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
    }
  }

  private var bottomRow: some View {
    HStack(spacing: 12) {
      RemoteButton("backward.fill") { onAction(.rewind) }
      RemoteButton("playpause.fill") { onAction(.playPause) }
      RemoteButton("forward.fill") { onAction(.forward) }
    }
  }

  private func circleButton(icon: String, action: RemoteAction) -> some View {
    RemoteButton(icon: icon, action: { onAction(action) }, style: .circle)
  }
}
