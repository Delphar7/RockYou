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
    GeometryReader { geo in
      let metrics = WatchLayoutMetrics(size: geo.size)

      VStack(spacing: metrics.pageTopPadding) {
        // Top row: Back, Home, Power
        HStack(spacing: metrics.topRowSpacing) {
          RemoteButton("chevron.left") { onAction(.back) }
          if let homeDelay = settings.watchHomeDelay, homeDelay > 0 {
            RemoteButton("house.fill") {}
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
          size: metrics.navDPadSize
        )

        Spacer(minLength: 0).frame(height: metrics.navBetweenDPadAndStrip)

        // App strip at bottom
        if let deviceId = deviceId {
          AppStripView(
            apps: apps,
            deviceId: deviceId,
            onLaunch: { app in
              onLaunchApp(app)
            },
            // Use fixed sizing so the strip respects the *page area's* height (percent sizing is screen-based).
            sizing: .fixed(iconWidth: nil, iconHeight: metrics.navAppStripIconHeight),
            showLabels: false,
            appLaunchDelay: settings.watchAppLaunchDelay
          )
          .background(
            GeometryReader { g in
              Color.clear
                .preference(
                  key: AppStripFramePreferenceKey.self,
                  value: g.frame(in: .named(NavPageCoordinateSpace.name))
                )
            }
          )
          // The strip can measure slightly taller than its visible content; reclaim a bit of vertical space
          // on small watches so the page indicator stays fully visible.
          .padding(.top, metrics.isSmallWatch ? -6 : -10)
          .padding(.bottom, 0)
        } else {
          Text("No Apps Loaded...")
            .font(.system(size: AppFontSize.small))
            .foregroundStyle(.secondary)
            .frame(height: 42)
        }

        PageIndicator(
          pageCount: pageCount,
          currentPage: currentPage,
          onPageTap: onPageTap,
          dotSize: metrics.pageIndicatorDotSize,
          spacing: metrics.pageIndicatorDotSpacing
        )
        .padding(.vertical, 0)
      }
      .padding(.horizontal, metrics.pageHorizontalPadding)
      .padding(.top, metrics.pageTopPadding)
      .frame(width: geo.size.width, height: geo.size.height)
    }
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
