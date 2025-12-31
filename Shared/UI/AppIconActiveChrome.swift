import SwiftUI

/// AppStrip-only "active app" chrome: inverting stroke + glow ring + pin stroke.
///
/// This is intentionally separated from `AppIcon` / `AppIconWithLabel` so only AppStrip (and other
/// strip-like surfaces) opt into this look.
extension View {
  @ViewBuilder
  func appIconActiveChrome<IconPixels: View>(
    isActive: Bool,
    glowPulseFactor: CGFloat,
    cornerRadius: CGFloat,
    @ViewBuilder iconPixels: @escaping () -> IconPixels
  ) -> some View {
    if isActive {
      overlay {
        AppIconActiveChromeOverlay(
          glowPulseFactor: glowPulseFactor,
          cornerRadius: cornerRadius,
          iconPixels: iconPixels
        )
      }
    } else {
      self
    }
  }
}

private struct AppIconActiveChromeOverlay<IconPixels: View>: View {
  private enum ActiveBorderStyle {
    // NOTE: These are intentionally computed (not stored) to avoid
    // "static stored properties not supported in generic types" in some targets/toolchains.
    static var invertingStrokeWidth: CGFloat { 2.5 }
    static var invertingStrokeOpacity: CGFloat { 0.8 }
    static var invertingStrokeSaturation: CGFloat { 0.5 }

    static var pinStrokeWidth: CGFloat { 1 }
    static var pinStrokeOpacity: CGFloat { 0.5 }
    static var pinGlowRadius: CGFloat { 2 }
  }

  let glowPulseFactor: CGFloat
  let cornerRadius: CGFloat
  @ViewBuilder let iconPixels: () -> IconPixels

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
      cornerRadius: cornerRadius + glowExtent + 6,
      style: .continuous
    )
    .inset(by: -glowExtent)

    ZStack {
      // Invert the icon pixels under the stroke (draw icon again and invert, masked to the stroke).
      iconPixels()
        .clipShape(shape)
        .colorInvert()
        .saturation(ActiveBorderStyle.invertingStrokeSaturation)
        .opacity(ActiveBorderStyle.invertingStrokeOpacity)
        .mask(shape.strokeBorder(lineWidth: ActiveBorderStyle.invertingStrokeWidth))

      // Glow ring (behind the perimeter), but only visible outside the icon.
      shape
        .stroke(
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
  }
}
