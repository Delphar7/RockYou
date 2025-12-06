//
//  NavPage.swift
//  RockYou Watch App
//
//  Navigation page with D-Pad and app strip
//

import SwiftUI
import WatchKit

struct NavPage: View {
  let pageCount: Int
  let currentPage: Int
  let apps: [RokuApp]
  let deviceId: String?
  let onAction: (RemoteAction) -> Void
  let onLaunchApp: (RokuApp) -> Void
  let onCrownChange: (Double, Double) -> Void
  let onSwipeLeft: () -> Void
  let onSwipeRight: () -> Void
  let onPageTap: (Int) -> Void
  let onAppear: () -> Void

  @State private var crownValue: Double = 50
  @State private var settings = WatchAppSettings.shared
  @State private var appStripFrame: CGRect = .zero
  @State private var isAppStripInteracting: Bool = false

  var body: some View {
    VStack(spacing: 6) {
      // Top row: Back, Home, Power
      HStack(spacing: 12) {
        RemoteButton("chevron.left") { onAction(.back) }
        if let homeDelay = settings.watchHomeDelay, homeDelay > 0 {
          RemoteButton("house.fill") { }
            .sweepable(
              icon: "house.fill",
              color: .indigo,
              delay: homeDelay,
              tooltip: "Hold to go home",
              onSweepComplete: { onAction(.home) }
            )
        } else {
          RemoteButton("house.fill") { onAction(.home) }
        }
        SafePowerButton(onPower: { onAction(.power) }, safetyDelay: settings.watchPowerDelay)
      }

      Spacer(minLength: 0)

      // D-Pad - hero element
      DPadView(
        onDirection: { onAction($0) },
        onOK: { onAction(.ok) },
        size: 80
      )

      Spacer(minLength: 0).frame(height: 14)

      // App strip at bottom
      if let deviceId = deviceId {
        AppStripView(
          apps: apps,
          deviceId: deviceId,
          onLaunch: { app in
            onLaunchApp(app)
          },
          // Labels are off here, so give the strip a bit more room (≈ +15% vs prior).
          sizing: .percent(17),
          showLabels: false,
          appLaunchDelay: settings.watchAppLaunchDelay
        )
        .background(
          GeometryReader { geo in
            Color.clear
              .preference(
                key: AppStripFramePreferenceKey.self,
                value: geo.frame(in: .named(NavPageCoordinateSpace.name))
              )
          }
        )
        // Reclaim bottom padding so the taller strip grows "down" instead of stealing space from the D-pad.
        .padding(.bottom, 0)
      } else {
        Text("No Apps Loaded...")
          .font(.system(size: AppFontSize.small))
          .foregroundStyle(.secondary)
          .frame(height: 42)
      }

      PageIndicator(pageCount: pageCount, currentPage: currentPage, onPageTap: onPageTap)
        .padding(.vertical, 2)
    }
    .padding(.horizontal, 8)
    .padding(.top, 4)
    .contentShape(Rectangle())
    .focusable()
    .coordinateSpace(name: NavPageCoordinateSpace.name)
    .digitalCrownRotation($crownValue, from: 0, through: 100, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
    .digitalCrownAccessory(.hidden)
    .onChange(of: crownValue) { oldValue, newValue in
      onCrownChange(oldValue, newValue)
    }
    .onPreferenceChange(AppStripFramePreferenceKey.self) { newFrame in
      appStripFrame = newFrame
    }
    .onPreferenceChange(AppStripInteractionActivePreferenceKey.self) { newValue in
      isAppStripInteracting = newValue
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 50, coordinateSpace: .named(NavPageCoordinateSpace.name))
        .onEnded { value in
          // Page swipe must not steal horizontal drags that begin on the AppStrip.
          if isAppStripInteracting { return }
          if appStripFrame.contains(value.startLocation) { return }
          // Fallback: if the touch begins near the bottom (where the strip lives), never page-swipe.
          // This guards against rare frame/startLocation mismatches on watchOS.
          if value.startLocation.y > 120 { return }
          let isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
          guard isHorizontal else { return }
          if value.translation.width < -50 { onSwipeLeft() }
          if value.translation.width > 50 { onSwipeRight() }
        }
    )
    .onAppear {
      onAppear()
    }
  }
}

// MARK: - Preference plumbing (NavPage-local)

private enum NavPageCoordinateSpace {
  static let name = "NavPageSpace"
}

private struct AppStripFramePreferenceKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}
