//
//  AppIconButton.swift
//  RockYou (Shared)
//
//  iOS/watchOS app icon button with sweepable support.
//

import SwiftUI

struct AppIconButton: View {
  let appId: String
  let appName: String
  let appType: String?
  let deviceId: String
  let config: AppIconConfig
  let isActiveApp: Bool
  let glowPulseFactor: CGFloat
  /// Hold-to-launch delay. If nil, sweepable is disabled and the icon is a normal tap-to-launch button.
  let launchDelay: TimeInterval?
  let action: () -> Void

  @ObservedObject private var cache = AppCacheManager.shared

  /// Check if this is a TV input (HDMI, AV, Tuner) rather than an app.
  private var isInput: Bool { AppIconClassifier.isInput(appId: appId, appType: appType) }

  var body: some View {
    // Reference iconVersion to trigger re-render when icons load
    let _ = cache.iconVersion

    // iOS/watchOS: Use sweepable for hold-to-confirm
    // Off = no sweepable, just tap-to-launch.
    if launchDelay == nil {
      Button(action: action) {
        AppStripAppIconTile(
          appId: appId,
          appName: appName,
          appType: appType,
          deviceId: deviceId,
          config: config,
          isActiveApp: isActiveApp,
          glowPulseFactor: glowPulseFactor
        )
      }
      .buttonStyle(.plain)
    } else {
      Button(action: {}) {
        AppStripAppIconTile(
          appId: appId,
          appName: appName,
          appType: appType,
          deviceId: deviceId,
          config: config,
          isActiveApp: isActiveApp,
          glowPulseFactor: glowPulseFactor
        )
      }
      .buttonStyle(.plain)
      .sweepable(
        icon: {
          AppIconWithLabel.sweepOverlayIcon(
            appId: appId,
            appName: appName,
            appType: appType,
            deviceId: deviceId,
            config: config
          )
        },
        color: isInput ? rokuPurple : AppBranding.color(for: appName, appId: appId),
        delay: launchDelay ?? 1.0,
        overlayDelay: 0.25,
        tooltip: "Hold to launch app channel",
        debugLabel: "appId=\(appId) name='\(appName)'",
        showTooltipOnEarlyRelease: true,
        gestureStyle: .simultaneous,
        onSweepComplete: action
      )
    }
  }
}

// MARK: - Convenience initializers

extension AppIconButton {
  init(
    appId: String,
    appName: String,
    appType: String?,
    deviceId: String,
    config: AppIconConfig,
    isActiveApp: Bool = false,
    action: @escaping () -> Void
  ) {
    self.appId = appId
    self.appName = appName
    self.appType = appType
    self.deviceId = deviceId
    self.config = config
    self.isActiveApp = isActiveApp
    self.glowPulseFactor = 1.0
    self.launchDelay = 1.0
    self.action = action
  }
}
