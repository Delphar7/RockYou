import SwiftUI

/// AppStrip-only "active app" chrome: inverting stroke + glow ring + pin stroke + diagonal shimmer.
///
/// This is intentionally separated from `AppIcon` / `AppIconWithLabel` so only AppStrip (and other
/// strip-like surfaces) opt into this look.
extension View {
  @ViewBuilder
  func appIconActiveChrome<IconPixels: View>(
    isActive: Bool,
    glowPulseFactor: CGFloat,
    cornerRadius: CGFloat,
    edgeLuminance: CGFloat? = nil,
    @ViewBuilder iconPixels: @escaping () -> IconPixels
  ) -> some View {
    if isActive {
      overlay {
        AppIconActiveChromeOverlay(
          glowPulseFactor: glowPulseFactor,
          cornerRadius: cornerRadius,
          edgeLuminance: edgeLuminance,
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

  private enum ShimmerStyle {
    /// Width of the gradient band in UnitPoint space (0…1).
    static var bandWidth: CGFloat { 0.12 }

    /// Luminance threshold: below → screen (lighten), above → colorBurn (darken).
    static var threshold: CGFloat { 0.5 }

    // Screen mode (dark icons): white band lightens.
    static var screenOpacity: CGFloat { 0.35 }

    // ColorBurn mode (light icons): gray band darkens.
    // Opacity ramps with luminance so near-white icons still show the effect.
    static var burnBaseOpacity: CGFloat { 0.22 }
    static var burnMaxOpacity: CGFloat { 0.48 }
  }

  let glowPulseFactor: CGFloat
  let cornerRadius: CGFloat
  let edgeLuminance: CGFloat?
  @ViewBuilder let iconPixels: () -> IconPixels

  @Environment(\.glowShimmerPhase) private var shimmerPhase

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

      // Diagonal shimmer: two-layer sweep (screen + multiply) for uniform
      // visibility across all icon luminances.
      shimmerOverlay(shape: shape)

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

  // MARK: - Diagonal Shimmer

  @ViewBuilder
  private func shimmerOverlay(shape: RoundedRectangle) -> some View {
    let phase = shimmerPhase
    if phase > 0 && phase < 1 {
      // Map phase (0…1) to a sweep position that traverses the full diagonal.
      // The band center moves from -bandWidth (off-screen left) to 1+bandWidth (off-screen right).
      let bw = ShimmerStyle.bandWidth
      let center = -bw + phase * (1.0 + 2 * bw)

      // Single band: luminance picks the blend mode, color, and opacity.
      let lum = edgeLuminance ?? 0.5
      let useScreen = lum < ShimmerStyle.threshold

      let bandColor: Color = useScreen ? .white : .gray
      let bandBlend: BlendMode = useScreen ? .screen : .colorBurn
      let bandOpacity: CGFloat = useScreen
        ? ShimmerStyle.screenOpacity
        : ShimmerStyle.burnBaseOpacity + (ShimmerStyle.burnMaxOpacity - ShimmerStyle.burnBaseOpacity) * ((lum - ShimmerStyle.threshold) / (1.0 - ShimmerStyle.threshold))

      Rectangle()
        .fill(
          LinearGradient(
            stops: shimmerStops(
              center: center, halfWidth: bw, color: bandColor, opacity: bandOpacity
            ),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .blendMode(bandBlend)
        .clipShape(shape)
    }
  }

  /// Build gradient stops for a narrow band centered at `center` (in 0…1 UnitPoint space).
  /// The band fades from clear → color → clear over `halfWidth` on each side.
  private func shimmerStops(
    center: CGFloat,
    halfWidth: CGFloat,
    color: Color,
    opacity: CGFloat
  ) -> [Gradient.Stop] {
    let lo = center - halfWidth
    let hi = center + halfWidth

    // Clamp stops to [0, 1]. When the band is partially off-screen,
    // the visible portion fades naturally.
    var stops: [Gradient.Stop] = []
    stops.append(.init(color: .clear, location: max(0, lo)))
    if center >= 0 && center <= 1 {
      stops.append(.init(color: color.opacity(opacity), location: center))
    }
    stops.append(.init(color: .clear, location: min(1, hi)))

    // Ensure we always have at least 2 stops and they're sorted.
    if stops.count < 2 {
      stops = [.init(color: .clear, location: 0), .init(color: .clear, location: 1)]
    }
    return stops
  }
}
