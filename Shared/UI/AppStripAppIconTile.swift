import SwiftUI

/// AppStrip-specific app icon rendering: tile + optional label + active "chrome".
///
/// This intentionally owns the glow/pulse chrome so other UI surfaces can use `AppIcon`
/// without inheriting strip-specific styling.
struct AppStripAppIconTile: View {
  let appId: String
  let appName: String
  let appType: String?
  let deviceId: String
  let config: AppIconConfig
  let isActiveApp: Bool
  let glowPulseFactor: CGFloat

  @ObservedObject private var cache = AppCacheManager.shared

  var body: some View {
    // Reference iconVersion to trigger re-render when icons load
    let _ = cache.iconVersion

    let isInputIcon = AppIconClassifier.isInput(appId: appId, appType: appType)
    let treatment: AppIconTreatment = {
      if isInputIcon {
        return config.showLabel ? .inputCenterByPanel() : .inputTopFit
      }
      return .normalFill
    }()
    let showEmbeddedLabel = (!config.showLabel && isInputIcon)
    let iconLuminance = cache.iconEdgeLuminance(for: appId, deviceId: deviceId)

    VStack(spacing: config.showLabel ? 4 : 0) {
      ZStack(alignment: .bottom) {
        let tile = AppIcon(
          image: cache.iconImage(for: appId, deviceId: deviceId),
          size: CGSize(width: config.width, height: config.height),
          cornerRadius: config.cornerRadius,
          treatment: treatment
        ) {
          if isInputIcon {
            AppIconWithLabel.inputPlaceholder(
              config: config,
              label: AppIconWithLabel.inputLabel(appName: appName)
            )
          } else {
            AppIconWithLabel.brandedPlaceholder(appName: appName, appId: appId, config: config)
          }
        }

        tile
          .appIconActiveChrome(
            isActive: isActiveApp,
            glowPulseFactor: glowPulseFactor,
            cornerRadius: config.cornerRadius,
            edgeLuminance: iconLuminance
          ) {
            // Pixels-only version used for inverting-stroke overlay.
            AppIcon(
              image: cache.iconImage(for: appId, deviceId: deviceId),
              size: CGSize(width: config.width, height: config.height),
              cornerRadius: config.cornerRadius,
              treatment: treatment,
              showsBorder: false
            ) {
              if isInputIcon {
                AppIconWithLabel.inputPlaceholder(
                  config: config,
                  label: AppIconWithLabel.inputLabel(appName: appName)
                )
              } else {
                AppIconWithLabel.brandedPlaceholder(appName: appName, appId: appId, config: config)
              }
            }
          }

        if showEmbeddedLabel {
          Text(appName)
            .font(.system(size: config.labelFont, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .truncationMode(.tail)
            .padding(.horizontal, 4)
            .padding(.bottom, AppIconWithLabel.embeddedLabelBottomPadding(config: config))
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
}
