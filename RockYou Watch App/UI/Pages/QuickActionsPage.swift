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
    VStack(spacing: 10) {
      // Row 1: Pause + Power
      HStack(spacing: 12) {
        RemoteButton("pause.fill", label: "Pause") { onAction(.playPause) }
        SafePowerButton(
          onPower: { onAction(.power) },
          style: .labeled,
          safetyDelay: settings.watchPowerDelay
        )
        .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
      }

      // Row 2: Back + Home
      HStack(spacing: 12) {
        RemoteButton("chevron.left", label: "Back") { onAction(.back) }
        if let homeDelay = settings.watchHomeDelay, homeDelay > 0 {
          RemoteButton("house.fill", label: "Home") { }
            .sweepable(
              icon: "house.fill",
              color: .indigo,
              delay: homeDelay,
              tooltip: "Hold to go home",
              onSweepComplete: { onAction(.home) }
            )
        } else {
          RemoteButton("house.fill", label: "Home") { onAction(.home) }
        }
      }

      // Row 3: Mute + Apps
      HStack(spacing: 12) {
        RemoteButton("speaker.slash.fill", label: "Mute") { onAction(.volumeMute) }
          .disabledForUnavailableHardwareControls(isAvailable: hardwareControlsAvailable)
        RemoteButton("square.grid.2x2.fill", label: "Apps") { onAppsPressed() }
      }

      Spacer(minLength: 0)
        .frame(maxHeight: 2)

      PageIndicator(pageCount: pageCount, currentPage: currentPage, onPageTap: onPageTap)
        .padding(.bottom, 2)
    }
    .padding(.horizontal, 8)
    .padding(.top, 12)
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
}
