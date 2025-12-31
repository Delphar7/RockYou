//
//  QuickActionsPage.swift
//  RockYou Watch App
//
//  Quick access to common actions: Pause, Power, Back, Home, Mute, Apps
//

import SwiftUI
import WatchKit

struct QuickActionsPage: View {
  let pageCount: Int
  let currentPage: Int
  let hardwareControlsAvailable: Bool
  let onAction: (RemoteAction) -> Void
  let onAppsPressed: () -> Void
  let onCrownChange: (Double, Double) -> Void
  let onSwipeLeft: () -> Void
  let onSwipeRight: () -> Void
  let onPageTap: (Int) -> Void

  @State private var crownValue: Double = 50
  @State private var settings = WatchAppSettings.shared

  var body: some View {
    GeometryReader { geo in
      let metrics = WatchLayoutMetrics(size: geo.size)
      let rowH = metrics.quickActionsButtonHeight

      VStack(spacing: metrics.quickActionsRowSpacing) {
        Spacer(minLength: 0)

        // Button cluster (centered vertically)
        VStack(spacing: metrics.quickActionsRowSpacing) {
          // Row 1: Pause + Power
          HStack(spacing: metrics.buttonRowSpacing) {
            labeledButton(icon: "pause.fill", label: "Pause", height: rowH) { onAction(.playPause) }
            SafePowerButton(
              onPower: { onAction(.power) },
              style: .custom(height: rowH, showLabel: true),
              safetyDelay: settings.watchPowerDelay
            )
            .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
          }

          // Row 2: Back + Home
          HStack(spacing: metrics.buttonRowSpacing) {
            labeledButton(icon: "chevron.left", label: "Back", height: rowH) { onAction(.back) }
            if let homeDelay = settings.watchHomeDelay, homeDelay > 0 {
              labeledButton(icon: "house.fill", label: "Home", height: rowH) { }
                .sweepable(
                  icon: "house.fill",
                  color: .indigo,
                  delay: homeDelay,
                  tooltip: "Hold to go home",
                  onSweepComplete: { onAction(.home) }
                )
            } else {
              labeledButton(icon: "house.fill", label: "Home", height: rowH) { onAction(.home) }
            }
          }

          // Row 3: Mute + Apps
          HStack(spacing: metrics.buttonRowSpacing) {
            labeledButton(icon: "speaker.slash.fill", label: "Mute", height: rowH) { onAction(.volumeMute) }
              .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
            labeledButton(icon: "square.grid.2x2.fill", label: "Apps", height: rowH) { onAppsPressed() }
          }
        }

        Spacer(minLength: 0)

        // Leave a slight breathing gap above the dots (helps small watches feel less cramped).
        PageIndicator(
          pageCount: pageCount,
          currentPage: currentPage,
          onPageTap: onPageTap,
          dotSize: metrics.pageIndicatorDotSize,
          spacing: metrics.pageIndicatorDotSpacing
        )
        .padding(.top, 2)
        .padding(.bottom, 2)
      }
      .padding(.horizontal, metrics.pageHorizontalPadding)
      .padding(.top, metrics.quickActionsTopPadding)
      .padding(.bottom, 2)
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

  private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    max(lo, min(hi, v))
  }

  private func labeledButton(icon: String, label: String, height: CGFloat, action: @escaping () -> Void) -> some View {
    let style = RemoteButtonStyle.custom(
      width: nil,
      height: height,
      isCircle: false,
      iconSize: height * 0.40,
      cornerRadius: 10
    )

    let seed: UInt64 = "\(icon)|\(label)|watch-qa".stableHash64

    let base =
      VStack(spacing: 2) {
        Image(systemName: icon)
          .font(.system(size: height * 0.40, weight: .semibold))
        Text(label)
          .font(.system(size: AppFontSize.small, weight: .medium))
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .frame(height: height)

    let decorated = RemoteButtonPlatform.decorateContent(
      base: base,
      style: style,
      baseColor: nil,
      buttonShape: AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    )

    return RemoteButtonPlatform.makeBody(
      action: action,
      content: decorated,
      style: style,
      baseColor: nil,
      materialSeed: seed
    )
  }
}
