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

  var body: some View {
    GeometryReader { geo in
      let metrics = WatchLayoutMetrics(size: geo.size)

      VStack(spacing: metrics.pageTopPadding) {
        // Top row: Back, Mute, Power
        topRow(spacing: metrics.topRowSpacing)

        Spacer(minLength: 0).frame(height: metrics.mediaTopGap)

        // D-Pad with corner buttons
        ZStack(alignment: .top) {
          DPadView(onDirection: { onAction($0) }, onOK: { onAction(.ok) }, size: metrics.dPadSize)
            // Keep the corner buttons pinned; only nudge the D-pad down.
            .offset(y: metrics.mediaDPadYOffset)

          HStack {
            circleButton(icon: "asterisk", action: .options, size: metrics.mediaCornerButtonSize)
            Spacer()
            circleButton(
              icon: "gobackward.15", action: .instantReplay, size: metrics.mediaCornerButtonSize)
          }
          .padding(.horizontal, 2)
        }

        Spacer(minLength: 0).frame(height: metrics.mediaBottomGap)

        // Bottom row: Rewind, Play/Pause, Forward
        bottomRow(spacing: metrics.buttonRowSpacing)

        PageIndicator(
          pageCount: pageCount,
          currentPage: currentPage,
          onPageTap: onPageTap,
          dotSize: metrics.pageIndicatorDotSize,
          spacing: metrics.pageIndicatorDotSpacing
        )
        .padding(.bottom, 2)
        .padding(.top, metrics.pageTopPadding)
      }
      .padding(.horizontal, metrics.pageHorizontalPadding)
      .padding(.top, metrics.pageTopPadding)
      .frame(width: geo.size.width, height: geo.size.height)
    }
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

  private func topRow(spacing: CGFloat) -> some View {
    HStack(spacing: spacing) {
      RemoteButton("chevron.left") { onAction(.back) }
      RemoteButton("speaker.slash.fill") { onAction(.volumeMute) }
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      SafePowerButton(onPower: { onAction(.power) }, safetyDelay: settings.watchPowerDelay)
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
    }
  }

  private func bottomRow(spacing: CGFloat) -> some View {
    HStack(spacing: spacing) {
      RemoteButton("backward.fill") { onAction(.rewind) }
      RemoteButton("playpause.fill") { onAction(.playPause) }
      RemoteButton("forward.fill") { onAction(.forward) }
    }
  }

  private func circleButton(icon: String, action: RemoteAction, size: CGFloat) -> some View {
    RemoteButton(
      icon: icon,
      action: { onAction(action) },
      style: .custom(
        width: size, height: size, isCircle: true, iconSize: size * 0.40, cornerRadius: nil)
    )
  }
}
