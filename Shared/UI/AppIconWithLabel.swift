//
//  AppIconWithLabel.swift
//  RockYou (Shared)
//
//  Shared visual rendering for app icons.
//  Used by platform-specific AppIconButton implementations.
//

import SwiftUI

// MARK: - App Icon Configuration

struct AppIconConfig {
  let width: CGFloat
  let height: CGFloat
  let cornerRadius: CGFloat
  let labelFont: CGFloat
  let showLabel: Bool
  let showShadow: Bool

  static let phoneDefault = AppIconConfig(
    width: 72, height: 54, cornerRadius: 8,
    labelFont: 10, showLabel: true, showShadow: true
  )

  static let macDefault = AppIconConfig(
    width: 60, height: 45, cornerRadius: 8,
    labelFont: 10, showLabel: true, showShadow: true
  )

  static func watchCompact(stripHeight: CGFloat, showLabel: Bool = true) -> AppIconConfig {
    let iconHeightRatio: CGFloat = showLabel ? 0.70 : 0.90
    let iconHeight = stripHeight * iconHeightRatio
    let iconWidth = iconHeight * (4.0 / 3.0)
    let cornerRadius = max(4, iconHeight * 0.15)
    let labelFont = max(8, stripHeight * 0.18)

    return AppIconConfig(
      width: iconWidth, height: iconHeight, cornerRadius: cornerRadius,
      labelFont: labelFont, showLabel: showLabel, showShadow: false
    )
  }
}

// MARK: - App Icon With Label

struct AppIconWithLabel: View {
  let appId: String
  let appName: String
  let appType: String?
  let deviceId: String
  let config: AppIconConfig

  @ObservedObject private var cache = AppCacheManager.shared
  @Environment(\.displayScale) private var displayScale

  static func embeddedLabelBottomPadding(config: AppIconConfig) -> CGFloat {
    // Smaller padding pushes the baseline closer to the bottom edge (desired for embedded labels).
    //
    // watchOS: the strip tiles are physically small; even ~1pt of bottom padding reads "too high".
    // We use `showShadow` as a practical proxy for watch sizing (watch strips set showShadow=false).
    if !config.showShadow {
      return min(0.35, max(0.10, config.labelFont * 0.025))  // e.g. font=8 → 0.20
    }

    // iOS/macOS: keep the original feel.
    return min(1.5, max(0.5, config.labelFont * 0.12))
  }

  var body: some View {
    // Reference iconVersion to trigger re-render when icons load
    let _ = cache.iconVersion

    // Roku input IDs are stable and explicit (e.g. tvinput.hdmi1, tvinput.cvbs).
    // Use this signal instead of guessing from pixel aspect ratio.
    let isInputIcon = AppIconClassifier.isInput(appId: appId, appType: appType)
    let treatment: AppIconTreatment = {
      if isInputIcon {
        // If the label is shown below the tile, center the "real" icon panel (which often has a built-in label strip).
        return config.showLabel ? .inputCenterByPanel() : .inputTopFit
      }
      return .normalFill
    }()
    let showEmbeddedLabel = (!config.showLabel && isInputIcon)

    VStack(spacing: config.showLabel ? 4 : 0) {
      ZStack(alignment: .bottom) {
        AppIcon(
          image: cache.iconImage(for: appId, deviceId: deviceId),
          size: CGSize(width: config.width, height: config.height),
          cornerRadius: config.cornerRadius,
          treatment: treatment
        ) {
          if isInputIcon {
            Self.inputPlaceholder(config: config, label: Self.inputLabel(appName: appName))
          } else {
            Self.brandedPlaceholder(appName: appName, appId: appId, config: config)
          }
        }

        if showEmbeddedLabel {
          Text(appName)
            .font(.system(size: config.labelFont, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            // Nudge label down: reduce baseline→bottom padding without shrinking the text.
            .padding(.bottom, Self.embeddedLabelBottomPadding(config: config))
            .frame(width: config.width + 2)
            .foregroundStyle(.white.opacity(0.92))
        }
      }
      .if(config.showShadow) { view in
        view.shadow(color: .black.opacity(AppOpacity.medium), radius: 2, x: 0, y: 1)
      }

      if config.showLabel {
        Text(appName)
          .font(.system(size: config.labelFont))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(width: config.width + 4)
          .foregroundStyle(.primary)
      }
    }
  }

  static func inputPlaceholder(config: AppIconConfig, label: String) -> some View {
    RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
      .fill(rokuPurple)
      .overlay {
        Text(label)
          .font(.system(size: config.height * 0.28, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
  }

  static func brandedPlaceholder(appName: String, appId: String, config: AppIconConfig) -> some View
  {
    RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
      .fill(AppBranding.color(for: appName, appId: appId))
      .overlay {
        Text(AppBranding.initials(for: appName, appId: appId))
          .font(.system(size: config.height * 0.35, weight: .bold))
          .foregroundStyle(.white)
      }
  }

  static func inputLabel(appName: String) -> String {
    let lower = appName.lowercased()
    if lower.contains("hdmi") {
      if let range = lower.range(of: "hdmi") {
        let afterHDMI = String(appName[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let firstChar = afterHDMI.first, firstChar.isNumber {
          return "HDMI\(firstChar)"
        }
      }
      return "HDMI"
    } else if lower.contains("tuner") || lower.contains("antenna") {
      return "TV"
    } else if lower.contains("av") {
      return "AV"
    }
    return String(appName.prefix(4)).uppercased()
  }

  static func sweepOverlayIcon(
    appId: String,
    appName: String,
    appType: String?,
    deviceId: String,
    config: AppIconConfig
  ) -> some View {
    let cache = AppCacheManager.shared
    let isInputIcon = AppIconClassifier.isInput(appId: appId, appType: appType)
    let treatment: AppIconTreatment = {
      if isInputIcon {
        return config.showLabel ? .inputCenterByPanel() : .inputTopFit
      }
      return .normalFill
    }()

    return AppIcon(
      image: cache.iconImage(for: appId, deviceId: deviceId),
      size: CGSize(width: config.width, height: config.height),
      cornerRadius: config.cornerRadius,
      treatment: treatment,
      showsBorder: false
    ) {
      if isInputIcon {
        inputPlaceholder(config: config, label: inputLabel(appName: appName))
      } else {
        brandedPlaceholder(appName: appName, appId: appId, config: config)
      }
    }
  }
}
