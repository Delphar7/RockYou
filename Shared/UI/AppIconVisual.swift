//
//  AppIconVisual.swift
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

// MARK: - App Icon Visual

struct AppIconVisual: View {
  let appId: String
  let appName: String
  let appType: String?
  let deviceId: String
  let config: AppIconConfig
  /// Whether this icon is the currently active app for the device.
  /// When false, the active highlight (and glow pulse) are not drawn.
  let isActiveApp: Bool
  /// Single-flight pulse factor supplied by the owning strip (1 = normal, 0 = off).
  let glowPulseFactor: CGFloat

  @ObservedObject private var cache = AppCacheManager.shared
  @Environment(\.displayScale) private var displayScale

  private static func embeddedLabelBottomPadding(config: AppIconConfig) -> CGFloat {
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

  // MARK: - Input icon centering

  private enum InputIconCentering {
    // Derived from `tmp/xbox.png` by detecting the green "panel" bounds (ignoring the bottom label strip),
    // then computing the delta needed to center that panel within the full icon frame:
    //
    //   offset = (bottomGap - topGap) / 2
    //
    // For xbox.png we measured topGap≈0.036, bottomGap≈0.241 → offset≈0.1025 (≈10% of tile height).
    // This keeps inputs nicely centered when labels are drawn *outside* the icon frame (config.showLabel == true).
    // Tuned by eye after measuring xbox.png's visible "panel" bounds.
    static let contentVerticalCenterOffsetFraction: CGFloat = 0.11

    // Some Roku input icons have a squared top border baked into the PNG.
    // Instead of mutating the image, we cut out a *narrow* strip near the top,
    // inset from the left/right edges so we don't eat into the rounded corners.
    //
    // Model:
    // - remove a rectangle at y = topTrimOffsetY ..< (topTrimOffsetY + topTrimHeight)
    // - only across x = topTrimInsetX ..< (width - topTrimInsetX)
    static let topTrimOffsetY: CGFloat = 0
    static let topTrimHeight: CGFloat = 1
    static let topTrimInsetX: CGFloat = 1
  }

  // MARK: - Active border styling (final)

  private enum ActiveBorderStyle {
    static let invertingStrokeWidth: CGFloat = 2.5
    static let invertingStrokeOpacity: CGFloat = 0.8
    static let invertingStrokeSaturation: CGFloat = 0.5

    static let pinStrokeWidth: CGFloat = 1
    static let pinStrokeOpacity: CGFloat = 0.5
    static let pinGlowOpacity: CGFloat = 0.90
    static let pinGlowRadius: CGFloat = 2
  }

  var body: some View {
    // Reference iconVersion to trigger re-render when icons load
    let _ = cache.iconVersion

    // Roku input IDs are stable and explicit (e.g. tvinput.hdmi1, tvinput.cvbs).
    // Use this signal instead of guessing from pixel aspect ratio.
    let isInputIcon = Self.isInput(appId: appId, appType: appType)
    let iconLayout: IconLayout = {
      if isInputIcon {
        // If the label is shown below the tile, center the "real" icon panel (which often has a built-in label strip).
        return config.showLabel ? .inputCenterByPanel : .inputTopFit
      }
      return .normalFill
    }()
    let showEmbeddedLabel = (!config.showLabel && isInputIcon)

    // Default (non-active) border.
    let inactiveBorderColor = Color.gray.opacity(AppOpacity.primary)
    let inactiveBorderWidth: CGFloat = 1

    VStack(spacing: config.showLabel ? 4 : 0) {
      let shape = RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
      ZStack(alignment: .bottom) {
        Self.iconImage(
          appId: appId,
          appName: appName,
          appType: appType,
          deviceId: deviceId,
          config: config,
          displayScale: displayScale,
          layout: iconLayout
        )
        .frame(width: config.width, height: config.height)

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
      .clipShape(shape)
      // Active overlays: inversion-stroke (masked icon invert) + outside-only glow ring + pin stroke.
      .overlay {
        if isActiveApp {
          // Make the "bright" phase more obvious by pushing the glow outward / more solid.
          // `glowPulseFactor` is absolute opacity (0..1). Treat baseline as "normal".
          let base = GlowPulseConfig.baseOpacity
          let upStrength01: CGFloat = {
            let denom = max(0.001, (1.0 - base))
            return max(0, min(1, (glowPulseFactor - base) / denom))
          }()

          // Fade-to-nothing should also collapse the blur/ring so it's obvious.
          let downStrength01: CGFloat = {
            let denom = max(0.001, base)
            return max(0, min(1, (base - glowPulseFactor) / denom))
          }()

          let baseLineWidth: CGFloat = ActiveBorderStyle.pinStrokeWidth + 2
          let dynamicLineWidth: CGFloat = baseLineWidth + (2 * upStrength01)

          let baseRadius = ActiveBorderStyle.pinGlowRadius
          let normalized = max(0, min(1, glowPulseFactor / max(0.001, base)))
          let dynamicGlowRadius: CGFloat = (baseRadius * normalized) + (5 * upStrength01)

          // Give the halo a bit more room before it gets clipped by the outside-only mask.
          // (We also add padding at the strip level to avoid edge clipping.)
          let glowClipPadding: CGFloat = 4
          let glowExtent: CGFloat = max(2, dynamicGlowRadius * 2 + 6 + glowClipPadding)
          // Avoid hard corners by expanding corner radius with the extent.
          // IMPORTANT: must also expand the shape bounds, otherwise the outside-only mask cancels out.
          let outerShape = RoundedRectangle(
            cornerRadius: config.cornerRadius + glowExtent + 6,
            style: .continuous
          )
          .inset(by: -glowExtent)

          ZStack {
            // Invert the icon pixels under the stroke (draw icon again and invert, masked to the stroke).
            Self.iconImage(
              appId: appId,
              appName: appName,
              appType: appType,
              deviceId: deviceId,
              config: config,
              layout: iconLayout
            )
            .frame(width: config.width, height: config.height)
            .clipShape(shape)
            .colorInvert()
            .saturation(ActiveBorderStyle.invertingStrokeSaturation)
            .opacity(ActiveBorderStyle.invertingStrokeOpacity)
            .mask(shape.strokeBorder(lineWidth: ActiveBorderStyle.invertingStrokeWidth))

            // Glow ring (behind the perimeter), but only visible outside the icon.
            shape
              .stroke(
                // `glowPulseFactor` is now an absolute opacity (0..1) driven by the strip.
                Color.white.opacity(glowPulseFactor),
                lineWidth: dynamicLineWidth
              )
              .blur(radius: dynamicGlowRadius)
              .mask(
                ZStack {
                  outerShape.fill(Color.white.opacity(1.0 - (0.35 * downStrength01)))
                  shape.fill(Color.black).blendMode(.destinationOut)
                }
                .compositingGroup()
              )

            // Crisp pin stroke on top.
            shape.strokeBorder(
              Color.white.opacity(ActiveBorderStyle.pinStrokeOpacity),
              lineWidth: ActiveBorderStyle.pinStrokeWidth
            )
          }
        } else {
          shape.stroke(inactiveBorderColor, lineWidth: inactiveBorderWidth)
        }
      }
      // Pulse timing is owned by `AppStripView` (single-flight per strip).
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

  static func sweepOverlayIcon(
    appId: String,
    appName: String,
    appType: String?,
    deviceId: String,
    config: AppIconConfig
  ) -> some View {
    iconImage(
      appId: appId,
      appName: appName,
      appType: appType,
      deviceId: deviceId,
      config: config,
      displayScale: 1,
      layout: .normalFill
    )
      .frame(width: config.width, height: config.height)
      .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
  }

  private enum IconLayout {
    case normalFill
    case inputTopFit
    case inputCenterByPanel
  }

  @ViewBuilder
  private static func iconImage(
    appId: String,
    appName: String,
    appType: String?,
    deviceId: String,
    config: AppIconConfig,
    displayScale: CGFloat = 1,
    layout: IconLayout = .normalFill
  ) -> some View {
    let cache = AppCacheManager.shared
    let isInput = Self.isInput(appId: appId, appType: appType)
    let snapToPixel: (CGFloat) -> CGFloat = { value in
      let s = max(1, displayScale)
      return (value * s).rounded() / s
    }

    if let image = cache.iconImage(for: appId, deviceId: deviceId) {
      switch layout {
      case .normalFill:
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      case .inputTopFit:
        VStack(spacing: 0) {
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
          Spacer(minLength: 0)
        }
      case .inputCenterByPanel:
        GeometryReader { geo in
          // Key detail: trimming must happen *before* the slide, otherwise we're just clipping empty space.
          // Also snap to pixels to avoid subpixel edge filtering artifacts.
          let slide = snapToPixel(
            geo.size.height * InputIconCentering.contentVerticalCenterOffsetFraction)
          let trimOffsetY = snapToPixel(InputIconCentering.topTrimOffsetY)
          let trimHeight = snapToPixel(InputIconCentering.topTrimHeight)
          let trimInsetX = snapToPixel(InputIconCentering.topTrimInsetX)
          image
            .resizable()
            .scaledToFit()
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            // Punch out the top border strip (center-only, inset from rounded corners).
            .mask {
              ZStack(alignment: .top) {
                Rectangle().fill(Color.white)
                Rectangle()
                  .fill(Color.black)
                  .frame(
                    width: max(0, geo.size.width - (2 * trimInsetX)),
                    height: max(0, trimHeight)
                  )
                  .offset(y: trimOffsetY)
                  .blendMode(.destinationOut)
              }
              .compositingGroup()
            }
            // Now slide the already-trimmed icon down for panel-centering.
            .offset(y: slide)
            .clipped()
        }
      }
    } else if isInput {
      inputPlaceholder(config: config, label: inputLabel(appName: appName))
    } else {
      brandedPlaceholder(appName: appName, appId: appId, config: config)
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

  static func isInput(appId: String, appType: String?) -> Bool {
    appId.hasPrefix("tvinput.") || (appType == "tvin")
  }
}

extension AppIconVisual {
  // Back-compat convenience initializer for non-AppStrip call sites.
  init(
    appId: String,
    appName: String,
    appType: String?,
    deviceId: String,
    config: AppIconConfig,
    glowPulseFactor: CGFloat
  ) {
    self.appId = appId
    self.appName = appName
    self.appType = appType
    self.deviceId = deviceId
    self.config = config
    self.isActiveApp = false
    self.glowPulseFactor = glowPulseFactor
  }
}
