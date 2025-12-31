//
//  AppIconButton+macOS.swift
//  RockYou (Shared)
//
//  macOS-specific app icon button - simple click-to-launch, no hold-to-confirm.
//  This allows drag scrolling to work naturally without gesture conflicts.
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
    /// Hold-to-launch delay - ignored on macOS (always click-to-launch)
    let launchDelay: TimeInterval?
    let action: () -> Void

    @ObservedObject private var cache = AppCacheManager.shared

    var body: some View {
      // Reference iconVersion to trigger re-render when icons load
      let _ = cache.iconVersion

      // macOS: Always use simple button clicks - no hold-to-confirm needed
      // Drag scrolling is handled by the macOS AppStrip scroll wrapper.
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
      glowPulseFactor: CGFloat,
      action: @escaping () -> Void
    ) {
      self.appId = appId
      self.appName = appName
      self.appType = appType
      self.deviceId = deviceId
      self.config = config
      self.isActiveApp = isActiveApp
      self.glowPulseFactor = glowPulseFactor
      self.launchDelay = nil  // macOS doesn't use launch delay
      self.action = action
    }

    init(
      appId: String,
      appName: String,
      appType: String?,
      deviceId: String,
      config: AppIconConfig,
      action: @escaping () -> Void
    ) {
      self.appId = appId
      self.appName = appName
      self.appType = appType
      self.deviceId = deviceId
      self.config = config
      self.isActiveApp = false
      self.glowPulseFactor = 1.0
      self.launchDelay = nil  // macOS doesn't use launch delay
      self.action = action
    }
  }
