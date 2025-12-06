import SwiftUI

/// iOS/macOS-only material button "chrome" intended to match the D-pad's manufactured look.
///
/// This file is deliberately standalone so we can tune it via Previews before wiring it into
/// mainline button views.
///
/// Texture: `Resources/PlasticTexture.png` (1k x 1k). We sample (crop) it, we do not scale it.
enum MaterialButtonEffect {
  // MARK: - Lighting direction

  /// Light direction for the "material" lighting: SW → NE, tilted 10° off vertical.
  private static let lightingTiltDegrees: CGFloat = 15

  /// The shade contribution relative to `lightingStrength`.
  /// Kept smaller than the highlight term so increasing `lightingStrength` mostly lifts the NE side.
  private static let lightingShadeFactor: CGFloat = 0.35

  /// Global intensity for the lighting overlay layer (post blend-mode).
  private static let lightingOverlayOpacity: CGFloat = 0.95

  // MARK: - Wall tint calibration
  //
  // Calibrated from swatches:
  // - target (D-pad wall): H≈258°, S≈0.584, V≈0.383
  // - current (Mute wall): H≈266°, S≈0.796, V≈0.460
  //
  // Net: rotate hue slightly toward the D-pad wall, reduce saturation, and darken a touch.
  // (We intentionally keep these subtle; too much makes the wall read “inky” and shifts hue past target.)
  private static let wallHueRotationDegrees: CGFloat = -6
  private static let wallSaturationScale: CGFloat = 0.58
  // Wall lightness policy (HSL):
  // - We want the wall darker than the face, but not allowed to fall below a visibility floor.
  // - This fixes “dark buttons lose the wall” without inventing lots of knobs.
  private static let wallMinLightness: CGFloat = 0.15
  private static let wallLightnessDrop: CGFloat = 0.10
  private static let wallMinLightnessBelowFace: CGFloat = 0.02

  /// The wall can get visually swallowed by dark backgrounds on smaller buttons.
  /// Apply a small brightness boost to wall-only layers, scaled up for smaller control sizes.
  private static let wallBrightnessBoostBase: CGFloat = 0.01
  private static let wallBrightnessBoostSmallExtra: CGFloat = 0.03
  private static let wallBrightnessBoostReferenceSize: CGFloat = 96  // ~large button
  private static let wallBrightnessBoostMinSize: CGFloat = 48         // ~small button
  private static let wallBrightnessBoostMax: CGFloat = 0.08

  // MARK: - Lip surface extension
  //
  // The lip should read like the *same material* as the face, just stepped down.
  // To achieve that, we extend the face lighting + texture onto the lip ring via masking.
  // This intentionally does NOT affect the face rendering (mask is lip-only).
  private static let lipSurfaceLightingOpacity: CGFloat = 0.55
  private static let lipSurfaceTextureOpacityScale: CGFloat = 0.55

  // MARK: - Color helpers (iOS/macOS)
  private static func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard let c = color.rgbaComponents() else { return nil }
    return (c.red, c.green, c.blue, c.alpha)
  }

  private static func rgbToHsl(r: CGFloat, g: CGFloat, b: CGFloat) -> (
    h: CGFloat, s: CGFloat, l: CGFloat
  ) {
    let maxv = max(r, max(g, b))
    let minv = min(r, min(g, b))
    let l = (maxv + minv) * 0.5
    let d = maxv - minv
    if d == 0 { return (0, 0, l) }
    let s = d / (1 - abs(2 * l - 1))
    var h: CGFloat = 0
    if maxv == r {
      h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
    } else if maxv == g {
      h = ((b - r) / d) + 2
    } else {
      h = ((r - g) / d) + 4
    }
    h /= 6
    if h < 0 { h += 1 }
    return (h, s, l)
  }

  private static func hslToRgb(h: CGFloat, s: CGFloat, l: CGFloat) -> (
    r: CGFloat, g: CGFloat, b: CGFloat
  ) {
    func hueToRgb(_ p: CGFloat, _ q: CGFloat, _ tIn: CGFloat) -> CGFloat {
      var t = tIn
      if t < 0 { t += 1 }
      if t > 1 { t -= 1 }
      if t < 1 / 6 { return p + (q - p) * 6 * t }
      if t < 1 / 2 { return q }
      if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
      return p
    }
    if s == 0 { return (l, l, l) }
    let q = l < 0.5 ? (l * (1 + s)) : (l + s - l * s)
    let p = 2 * l - q
    return (hueToRgb(p, q, h + 1 / 3), hueToRgb(p, q, h), hueToRgb(p, q, h - 1 / 3))
  }

  private static func wallColorClamped(baseColor: Color, wallBoost: CGFloat, wallExtraDrop: CGFloat)
    -> Color
  {
    guard let rgba = rgba(baseColor) else { return baseColor }
    let face = rgbToHsl(r: rgba.r, g: rgba.g, b: rgba.b)

    // Hue/sat mapping (keep intent from earlier tuning).
    var h = face.h + (wallHueRotationDegrees / 360.0)
    if h < 0 { h += 1 }
    if h > 1 { h -= 1 }
    let s = max(0, min(1, face.s * wallSaturationScale))

    // Lightness policy: darker than face, but clamped to a floor.
    var l = face.l - (wallLightnessDrop + wallExtraDrop)
    l = max(l, wallMinLightness)
    l = min(l, max(0, face.l - wallMinLightnessBelowFace))

    // Small size-based visibility nudge (applied in HSL space so hue/sat stay stable).
    l = max(0, min(1, l + wallBoost))
    l = min(l, max(0, face.l - wallMinLightnessBelowFace))

    let rgb = hslToRgb(h: h, s: s, l: l)
    return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: rgba.a)
  }

  private static func shouldUseWallClamp(baseColor: Color, wallExtraDrop: CGFloat) -> Bool {
    guard let rgba = rgba(baseColor) else { return false }
    let face = rgbToHsl(r: rgba.r, g: rgba.g, b: rgba.b)
    let desired = face.l - (wallLightnessDrop + wallExtraDrop)
    return desired < wallMinLightness
  }

  // MARK: - Lip highlight scaling (dark base colors)
  //
  // The outer lip highlight stroke uses a positive `brightness(...)` lift.
  // On darker base colors, that same lift reads “hotter” (too bright), so we scale it down
  // relative to the `rokuPurple` baseline.
  private static let lipOuterHighlightMinScale: CGFloat = 0.55

  private static func lipOuterHighlightScale(baseColor: Color) -> CGFloat {
    guard let rgbaBase = rgba(baseColor), let rgbaRef = rgba(rokuPurple) else { return 1 }
    let lBase = rgbToHsl(r: rgbaBase.r, g: rgbaBase.g, b: rgbaBase.b).l
    let lRef = rgbToHsl(r: rgbaRef.r, g: rgbaRef.g, b: rgbaRef.b).l
    // Identity for `rokuPurple` (lBase == lRef ⇒ 1.0). Darker bases reduce scale.
    let ratio = lRef > 0.0001 ? (lBase / lRef) : 1
    return max(lipOuterHighlightMinScale, min(1, ratio))
  }

  /// Start point (darker) and end point (brighter) for lighting masks/gradients.
  private static var lightingStartEnd: (start: UnitPoint, end: UnitPoint) {
    // Treat the gradient as primarily vertical, but skewed slightly toward SW→NE.
    // We pin to top/bottom edges (dy = 0.5) and compute horizontal skew from tan(theta).
    let dy: CGFloat = 0.5
    let radians = lightingTiltDegrees * .pi / 180
    let dx = dy * tan(radians)

    let start = UnitPoint(x: 0.5 - dx, y: 0.5 + dy)  // SW-ish
    let end = UnitPoint(x: 0.5 + dx, y: 0.5 - dy)  // NE-ish
    return (start: start, end: end)
  }

  // MARK: - Metrics

  struct Metrics: Sendable {
    let lipWidth: CGFloat
    /// Subtle "step" fill for the lip ring (helps it read as geometry, not just an edge highlight).
    let lipRidgeOpacity: CGFloat
    let lipRidgeDarkening: CGFloat
    let pressDepth: CGFloat
    let liftHeight: CGFloat
    let sideDarkening: CGFloat
    /// Extra darkening applied to the *wall* layers (base thickness + lift shadow).
    /// This should not affect the face shading.
    let wallExtraDarkening: CGFloat
    let bottomEdgeHighlightOpacity: CGFloat
    let highlightBrightness: CGFloat
    let lipHighlightOpacityTop: CGFloat
    let lipHighlightOpacityBottom: CGFloat
    let lipShadowOpacityTop: CGFloat
    let lipShadowOpacityBottom: CGFloat
    let liftTintOpacityTop: CGFloat
    let liftTintOpacityBottom: CGFloat

    // Depth / lift shadow (unpressed)
    let liftShadowOpacity: CGFloat
    let liftShadowBlur: CGFloat
    let liftShadowOffsetY: CGFloat

    // Depth / lift shadow (pressed)
    let pressedLiftShadowOpacity: CGFloat
    let pressedLiftShadowBlur: CGFloat
    let pressedLiftShadowOffsetY: CGFloat

    // Lighting and texture
    let lightingStrength: CGFloat
    let textureOpacity: CGFloat
    let textureBlendMode: BlendMode

    static let standard = Metrics(
      lipWidth: 2.0,
      // Make the lip read a touch more like geometry (step) and less like a faint highlight.
      lipRidgeOpacity: 0.18,
      lipRidgeDarkening: 0.09,
      pressDepth: 5,
      liftHeight: 6,
      sideDarkening: 0.16,
      wallExtraDarkening: 0.05,
      bottomEdgeHighlightOpacity: 0.2,
      highlightBrightness: 0.10,
      lipHighlightOpacityTop: 0.9,
      lipHighlightOpacityBottom: 0.8,
      lipShadowOpacityTop: 0.07,
      lipShadowOpacityBottom: 0.30,
      liftTintOpacityTop: 0.0,
      liftTintOpacityBottom: 0.35,
      liftShadowOpacity: 0.18,
      liftShadowBlur: 10,
      liftShadowOffsetY: 6,
      pressedLiftShadowOpacity: 0.08,
      pressedLiftShadowBlur: 5,
      pressedLiftShadowOffsetY: 2,
      // Tuned to better match the D-pad *lit-side* look while keeping the shadow side from getting crushed.
      lightingStrength: 0.40,
      textureOpacity: 0.22,
      textureBlendMode: .softLight,
    )
  }

  // MARK: - Public API

  /// Apply a material chrome effect to a rounded-rect background.
  ///
  /// - Parameters:
  ///   - baseColor: The face color (caller-provided).
  ///   - isPressed: Controls press animation.
  ///   - seed: Stable seed so texture sampling doesn't "jump".
  ///   - metrics: Tunable parameters.
  static func roundedRect(
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    cornerRadius: CGFloat = 14,
    metrics: Metrics = .standard
  ) -> some View {
    chrome(
      shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
      baseColor: baseColor,
      isPressed: isPressed,
      seed: seed,
      metrics: metrics
    )
  }

  /// Apply a material chrome effect to a circular background.
  static func circle(
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    metrics: Metrics = .standard
  ) -> some View {
    chrome(
      shape: Circle(),
      baseColor: baseColor,
      isPressed: isPressed,
      seed: seed,
      metrics: metrics
    )
  }

  /// Apply a material chrome effect to a capsule background (e.g. Power button).
  static func capsule(
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    metrics: Metrics = .standard
  ) -> some View {
    chrome(
      shape: Capsule(),
      baseColor: baseColor,
      isPressed: isPressed,
      seed: seed,
      metrics: metrics
    )
  }

  /// Apply a material chrome effect to a capsule background with content bound to the press animation.
  static func capsuleWithContent<Content: View>(
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    metrics: Metrics = .standard,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    chromeWithContent(
      shape: Capsule(),
      baseColor: baseColor,
      isPressed: isPressed,
      seed: seed,
      metrics: metrics,
      content: content
    )
  }

  // MARK: - Implementation

  private static func chromeWithContent<S: InsettableShape, Content: View>(
    shape: S,
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    metrics: Metrics,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    GeometryReader { geo in
      let size = geo.size
      let minSide = min(size.width, size.height)
      let liftHeight = min(metrics.liftHeight, max(3, minSide * 0.14))
      let pressDepth = min(metrics.pressDepth, liftHeight)
      let faceOffsetY = isPressed ? pressDepth : 0
      let visibleLift = max(0, liftHeight - faceOffsetY)

      let liftOpacity = isPressed ? metrics.pressedLiftShadowOpacity : metrics.liftShadowOpacity
      let liftBlur = isPressed ? metrics.pressedLiftShadowBlur : metrics.liftShadowBlur
      let liftOffsetY = isPressed ? metrics.pressedLiftShadowOffsetY : metrics.liftShadowOffsetY

      let wallMask = wallMask(shape: shape, wallOffsetY: visibleLift)
      // Scale brightness boost up for small buttons (they read darker against the black background).
      let wallBoostT = max(
        0,
        min(
          1,
          (wallBrightnessBoostReferenceSize - minSide)
            / (wallBrightnessBoostReferenceSize - wallBrightnessBoostMinSize)
        )
      )
      let wallBrightnessBoost = min(
        wallBrightnessBoostMax,
        wallBrightnessBoostBase
          + (wallBrightnessBoostSmallExtra * wallBoostT)
      )

      let lightingStrength = metrics.lightingStrength

      ZStack {
        // Wall layers (never hit-test).
        ZStack {
          let useClamp = shouldUseWallClamp(
            baseColor: baseColor, wallExtraDrop: metrics.wallExtraDarkening)
          let clampedWallColor = wallColorClamped(
            baseColor: baseColor,
            wallBoost: wallBrightnessBoost,
            wallExtraDrop: metrics.wallExtraDarkening
          )

          // Base thickness: darker "vertical side" that peeks out below the face.
          Group {
            if useClamp {
              shape.fill(clampedWallColor)
            } else {
              // Original wall rendering: derive wall from baseColor via view modifiers.
              // Keeps the “good” `rokuPurple` walls identical to the pre-clamp look.
              shape
                .fill(baseColor)
                .brightness(-Double(metrics.sideDarkening + metrics.wallExtraDarkening))
                .saturation(wallSaturationScale)
                .hueRotation(.degrees(wallHueRotationDegrees))
                .brightness(Double(wallBrightnessBoost))
            }
          }
          .offset(x: 0, y: visibleLift)
          .mask(wallMask)

          // Depth / lift "shadow": should be a darker shade of the button color (not black-on-background).
          Group {
            if useClamp {
              shape.fill(clampedWallColor)
            } else {
              shape
                .fill(baseColor)
                .brightness(-Double(metrics.sideDarkening + metrics.wallExtraDarkening))
                .saturation(wallSaturationScale)
                .hueRotation(.degrees(wallHueRotationDegrees))
                .brightness(Double(wallBrightnessBoost))
            }
          }
          .opacity(liftOpacity)
          .blur(radius: liftBlur)
          .offset(x: 0, y: liftOffsetY + visibleLift)
          .mask(
            // Weight the lift tint toward the bottom.
            LinearGradient(
              colors: [
                Color.white.opacity(metrics.liftTintOpacityTop),
                Color.white.opacity(
                  (metrics.liftTintOpacityTop + metrics.liftTintOpacityBottom) * 0.5),
                Color.white.opacity(metrics.liftTintOpacityBottom),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .mask(wallMask)
        }
        .allowsHitTesting(false)

        // Face + content: slide together on press.
        ZStack {
          shape.fill(baseColor)

          // Lighting gradient: subtle shading + highlight (closer to the pre-rendered D-pad).
          // We keep the darkening term *much* smaller than the highlight so the base doesn't get crushed.
          let (lightStart, lightEnd) = lightingStartEnd
          shape
            .fill(
              LinearGradient(
                colors: [
                  // Keep the shade term smaller than highlight so increasing `lightingStrength` mostly
                  // pushes the lit-side (NE) rather than darkening the whole face.
                  Color.black.opacity(lightingStrength * lightingShadeFactor),  // subtle shade on SW
                  Color.white.opacity(lightingStrength),  // brighter on NE
                ],
                startPoint: lightStart,
                endPoint: lightEnd
              )
            )
            .blendMode(.overlay)
            .opacity(lightingOverlayOpacity)

          // Texture: cookie-cutter crop from the 1k source, no scaling.
          textureOverlay(size: size, seed: seed)
            .blendMode(metrics.textureBlendMode)
            .opacity(metrics.textureOpacity)
            .mask(shape)

          // A thin bright edge at the *bottom* of the face to imply an edge catching light.
          // This is separate from the lip and helps sell the "lift" / height.
          shape
            .strokeBorder(baseColor, lineWidth: 1)
            .brightness(Double(metrics.highlightBrightness))
            .opacity(metrics.bottomEdgeHighlightOpacity)
            .mask(
              // Mostly bottom-weighted, but modulated by the same SW→NE lighting direction
              // so it doesn't look "stuck" to screen-up/down.
              ZStack {
                LinearGradient(
                  colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.0),
                    Color.white.opacity(1.0),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )

                LinearGradient(
                  colors: [
                    // Keep some baseline so the "back" side doesn't go to zero.
                    Color.white.opacity(0.75),
                    Color.white.opacity(1.0),
                  ],
                  startPoint: lightStart,
                  endPoint: lightEnd
                )
                .blendMode(.multiply)
              }
              .compositingGroup()
            )

          // Lip ridge fill: a *very* subtle ring fill so the lip reads as a step,
          // even when the highlight stroke is faint on the unlit side.
          //
          // IMPORTANT: Light source is near the top/back (power button). That means the *back/top* lip
          // should read brighter, while the front/bottom lip is slightly occluded in shadow.
          shape
            .fill(baseColor)
            .brightness(-Double(metrics.lipRidgeDarkening))
            .opacity(metrics.lipRidgeOpacity)
            .mask(
              lipRingMask(shape: shape, inset: metrics.lipWidth * 2)
                .mask(
                  // This is a *darkening* layer: apply it more strongly toward the bottom/front,
                  // so the bottom lip doesn't read brighter just because it's next to a darker face region.
                  LinearGradient(
                    colors: [
                      Color.white.opacity(0.0),
                      Color.white.opacity(1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
            )

          // Extend the face's lighting + texture onto the lip ring (material continuity),
          // without affecting the face at all.
          shape
            .fill(
              LinearGradient(
                colors: [
                  Color.black.opacity(lightingStrength * lightingShadeFactor),
                  Color.white.opacity(lightingStrength),
                ],
                startPoint: lightStart,
                endPoint: lightEnd
              )
            )
            .blendMode(.overlay)
            .opacity(lipSurfaceLightingOpacity)
            .mask(lipRingMask(shape: shape, inset: metrics.lipWidth * 2))

          textureOverlay(size: size, seed: seed)
            .blendMode(metrics.textureBlendMode)
            .opacity(metrics.textureOpacity * lipSurfaceTextureOpacityScale)
            .mask(lipRingMask(shape: shape, inset: metrics.lipWidth * 2))

          // Bottom lip "step band": should sit between the face and the wall.
          // Slightly more shadowed than the face, but not as dark as the wall.
          shape
            .fill(baseColor)
            .brightness(-Double(metrics.sideDarkening * 0.55))
            .opacity(0.34)
            .mask(
              lipRingMask(shape: shape, inset: metrics.lipWidth * 1.4)
                .mask(
                  LinearGradient(
                    colors: [
                      Color.white.opacity(0.0),
                      Color.white.opacity(0.0),
                      Color.white.opacity(1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                  )
                )
            )

          // Lip: thin/shallow perimeter step.
          // Make it respond to the same SW→NE lighting direction (so it doesn't vanish on the "back" side).
          let lipHighlightScale = lipOuterHighlightScale(baseColor: baseColor)
          shape
            .strokeBorder(baseColor, lineWidth: metrics.lipWidth)
            .brightness(Double(metrics.highlightBrightness * lipHighlightScale))
            .mask(
              // Combine diagonal SW→NE lighting with a vertical bias (top/back brighter).
              ZStack {
                LinearGradient(
                  colors: [
                    // Lower opacity on the SW (darker side), higher on the NE (lit side).
                    Color.white.opacity(metrics.lipHighlightOpacityBottom * lipHighlightScale),
                    Color.white.opacity(metrics.lipHighlightOpacityTop * lipHighlightScale),
                  ],
                  startPoint: lightStart,
                  endPoint: lightEnd
                )

                LinearGradient(
                  colors: [
                    Color.white.opacity(1.0),
                    Color.white.opacity(0.0),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
                .blendMode(.multiply)
              }
              .compositingGroup()
            )

          // Inner shadow ring (slightly stronger on the SW/darker side).
          shape
            .inset(by: metrics.lipWidth)
            .strokeBorder(baseColor, lineWidth: metrics.lipWidth)
            .brightness(-Double(metrics.sideDarkening * 0.78))
            .mask(
              // Combine diagonal SW→NE with vertical bias (bottom/front more shadow).
              ZStack {
                LinearGradient(
                  colors: [
                    // Stronger shadow on the SW (darker side), weaker on the NE (lit side).
                    Color.white.opacity(metrics.lipShadowOpacityBottom),
                    Color.white.opacity(metrics.lipShadowOpacityTop),
                  ],
                  startPoint: lightStart,
                  endPoint: lightEnd
                )

                LinearGradient(
                  colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(1.0),
                  ],
                  startPoint: .top,
                  endPoint: .bottom
                )
                .blendMode(.multiply)
              }
              .compositingGroup()
            )

          // Content (glyph/text) should slide with the face so it never "floats" on press.
          content()
            .frame(width: size.width, height: size.height, alignment: .center)
        }
        .offset(x: 0, y: faceOffsetY)
      }
      .frame(width: size.width, height: size.height)
      .animation(.snappy(duration: 0.12), value: isPressed)
    }
  }

  private static func chrome<S: InsettableShape>(
    shape: S,
    baseColor: Color,
    isPressed: Bool,
    seed: UInt64,
    metrics: Metrics
  ) -> some View {
    chromeWithContent(
      shape: shape,
      baseColor: baseColor,
      isPressed: isPressed,
      seed: seed,
      metrics: metrics
    ) {
      // No content: background-only chrome.
      EmptyView()
    }
  }

  /// A mask that yields only the region of `shape.offset(y: wallOffsetY)` that is *not* covered by `shape`.
  /// In other words, it isolates the "vertical wall" between the face and the base.
  private static func wallMask<S: InsettableShape>(shape: S, wallOffsetY: CGFloat) -> some View {
    ZStack {
      shape
        .fill(Color.white)
        .offset(x: 0, y: wallOffsetY)

      // Punch out the face area, leaving only the exposed wall.
      shape
        .fill(Color.black)
        .blendMode(.destinationOut)
    }
    .compositingGroup()
  }

  /// A mask that yields only a thin ring around the shape's perimeter.
  /// This helps the lip read as geometry (a step) rather than only a specular edge highlight.
  private static func lipRingMask<S: InsettableShape>(shape: S, inset: CGFloat) -> some View {
    ZStack {
      shape
        .fill(Color.white)

      shape
        .inset(by: inset)
        .fill(Color.black)
        .blendMode(.destinationOut)
    }
    .compositingGroup()
  }

  // MARK: - ButtonStyle (for real UI)

  struct RoundedRectStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let baseColor: Color
    let seed: UInt64
    var cornerRadius: CGFloat = 14
    var metrics: Metrics = .standard

    func makeBody(configuration: Configuration) -> some View {
      let pressed = configuration.isPressed && isEnabled
      configuration.label
        // Keep the label driving layout size and hit-testing, but render the visible chrome+label
        // in *one* overlay tree so the glyph can't "chase" the animation.
        // NOTE: Do NOT use `.opacity(0)` here: UIKit will ignore hit-testing for views whose
        // alpha is effectively 0, causing taps to fall through and hit controls below.
        //
        // ALSO: Do NOT replace the label with `Color.clear` in debug sampling modes.
        // A fully-transparent/empty label can become effectively non-hittable in some SwiftUI/UIView
        // compositions. We *force* a concrete hit-test shape here to prevent regressions
        // (this has broken input multiple times due to GeometryReader + transparency interactions).
        .foregroundStyle(Color.clear)
        .tint(.clear)
        // Breadcrumb: this is required for reliable hit-testing when the label is visually transparent.
        // Keep it on the *base* label (the overlay chrome is hit-testing disabled).
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
          MaterialButtonEffect.chromeWithContent(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            baseColor: baseColor,
            isPressed: pressed,
            seed: seed,
            metrics: metrics
          ) {
            configuration.label
          }
          // Critical: chrome overlay must never affect hit-testing. The invisible base label
          // is what receives touches.
          .allowsHitTesting(false)
        }
    }
  }

  struct CircleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let baseColor: Color
    let seed: UInt64
    var metrics: Metrics = .standard

    func makeBody(configuration: Configuration) -> some View {
      let pressed = configuration.isPressed && isEnabled
      configuration.label
        // See `RoundedRectStyle` for hit-testing notes. Same constraints apply here.
        .foregroundStyle(Color.clear)
        .tint(.clear)
        .contentShape(Circle())
        .overlay {
          MaterialButtonEffect.chromeWithContent(
            shape: Circle(),
            baseColor: baseColor,
            isPressed: pressed,
            seed: seed,
            metrics: metrics
          ) {
            configuration.label
          }
          .allowsHitTesting(false)
        }
    }
  }

  struct CapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let baseColor: Color
    let seed: UInt64
    var metrics: Metrics = .standard

    func makeBody(configuration: Configuration) -> some View {
      let pressed = configuration.isPressed && isEnabled
      configuration.label
        .foregroundStyle(Color.clear)
        .tint(.clear)
        .contentShape(Capsule())
        .overlay {
          MaterialButtonEffect.chromeWithContent(
            shape: Capsule(),
            baseColor: baseColor,
            isPressed: pressed,
            seed: seed,
            metrics: metrics
          ) {
            configuration.label
          }
          .allowsHitTesting(false)
        }
    }
  }

  private static func textureOverlay(size: CGSize, seed: UInt64) -> some View {
    return AnyView(textureOverlaySingle(size: size, seed: seed))
  }

  private static func textureOverlaySingle(size: CGSize, seed: UInt64) -> some View {
    // We treat the texture as a 1k×1k canvas in points (because it's a loose resource, not an asset catalog variant).
    // We "cookie-cutter" crop a random region of that canvas into the button, with a stable seed.
    let textureSize: CGFloat = 1024

    // Safety: if the view is larger than the texture, fall back to tiling behavior via resizable(tile).
    if size.width > textureSize || size.height > textureSize {
      return AnyView(
        textureImage()
          .resizable(resizingMode: .tile)
      )
    }

    var rng = XorShift64Star(seed: seed == 0 ? 0xBAD5EED : seed)
    let u = rng.nextUnit()
    let v = rng.nextUnit()

    let maxX = max(textureSize - size.width, 0)
    let maxY = max(textureSize - size.height, 0)

    // Snap to half-pixels to reduce shimmer on animated resizes, but keep it deterministic.
    let cropX = floor((u * maxX) * 2) / 2
    let cropY = floor((v * maxY) * 2) / 2

    return AnyView(
      ZStack(alignment: .topLeading) {
        textureImage()
          .offset(x: -cropX, y: -cropY)
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
      .clipped()
    )
  }

  private static func textureImage() -> Image {
    if let path = Bundle.main.path(forResource: "PlasticTexture", ofType: "png"),
      let image = PlatformSwiftUIImage.contentsOfFile(path)
    {
      return image
    }

    DebugBuild.run {
      Log.warn(
        "MaterialButton",
        "Missing texture resource: PlasticTexture.png (bundle=\(Bundle.main.bundleIdentifier ?? "nil"))"
      )
    }
    return Image(systemName: "exclamationmark.triangle.fill")
  }

  // MARK: - Deterministic RNG (stable texture crop)

  private struct XorShift64Star {
    private var state: UInt64

    init(seed: UInt64) {
      self.state = seed == 0 ? 0xDEAD_BEEF_CAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
      var x = state
      x ^= x >> 12
      x ^= x << 25
      x ^= x >> 27
      state = x
      return x &* 2_685_821_657_736_338_717
    }

    mutating func nextUnit() -> CGFloat {
      // [0, 1)
      let v = next() >> 11
      return CGFloat(Double(v) / Double(1 << 53))
    }
  }
}

// MARK: - Previews

#Preview("MaterialButtonEffect playground") {
  ScrollView {
    VStack(alignment: .leading, spacing: 18) {
      Text("MaterialButtonEffect playground")
        .font(.system(.title2, design: .rounded).weight(.bold))
        .foregroundStyle(.white)

      Text("Before = flat fill + thin border. After = material (lip + lift + texture + lighting).")
        .font(.callout)
        .foregroundStyle(.white.opacity(0.7))

      Group {
        Text("Rounded rects")
          .font(.headline)
          .foregroundStyle(.white.opacity(0.9))

        HStack(spacing: 18) {
          previewRoundedLabeled(
            title: "Before", systemName: "chevron.left", seed: 1, style: .flat, pressed: false)
          previewRoundedLabeled(
            title: "After", systemName: "chevron.left", seed: 1, style: .material, pressed: false)
          previewRoundedLabeled(
            title: "After (pressed)", systemName: "chevron.left", seed: 1, style: .material,
            pressed: true)
        }

        HStack(spacing: 18) {
          previewRoundedLabeled(
            title: "Before", systemName: "house", seed: 2, style: .flat, pressed: false)
          previewRoundedLabeled(
            title: "After", systemName: "house", seed: 2, style: .material, pressed: false)
          previewRoundedLabeled(
            title: "After (pressed)", systemName: "house", seed: 2, style: .material, pressed: true)
        }

        HStack(spacing: 18) {
          previewRoundedLabeled(
            title: "Before", systemName: "gearshape", seed: 3, style: .flat, pressed: false)
          previewRoundedLabeled(
            title: "After", systemName: "gearshape", seed: 3, style: .material, pressed: false)
          previewRoundedLabeled(
            title: "After (pressed)", systemName: "gearshape", seed: 3, style: .material,
            pressed: true)
        }
      }

      Divider().overlay(Color.white.opacity(0.12))

      Group {
        Text("Circles")
          .font(.headline)
          .foregroundStyle(.white.opacity(0.9))

        HStack(spacing: 26) {
          previewCircleLabeled(title: "Before", systemName: "backward.fill", seed: 11, style: .flat)
          previewCircleLabeled(
            title: "After", systemName: "backward.fill", seed: 11, style: .material)
          previewCircleLabeled(
            title: "After (pressed)", systemName: "backward.fill", seed: 11, style: .material,
            pressed: true)
        }

        HStack(spacing: 26) {
          previewCircleLabeled(
            title: "Before", systemName: "playpause.fill", seed: 12, style: .flat)
          previewCircleLabeled(
            title: "After", systemName: "playpause.fill", seed: 12, style: .material)
          previewCircleLabeled(
            title: "After (pressed)", systemName: "playpause.fill", seed: 12, style: .material,
            pressed: true)
        }

        HStack(spacing: 26) {
          previewCircleLabeled(title: "Before", systemName: "forward.fill", seed: 13, style: .flat)
          previewCircleLabeled(
            title: "After", systemName: "forward.fill", seed: 13, style: .material)
          previewCircleLabeled(
            title: "After (pressed)", systemName: "forward.fill", seed: 13, style: .material,
            pressed: true)
        }
      }
    }
    .padding(24)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
}

private enum PreviewStyle { case flat, material }

private let previewPurple = Color(red: 0.40, green: 0.20, blue: 0.55)

private func previewRoundedLabeled(
  title: String,
  systemName: String,
  seed: UInt64,
  style: PreviewStyle,
  pressed: Bool = false
) -> some View {
  VStack(spacing: 6) {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white.opacity(0.75))

    ZStack {
      Group {
        switch style {
        case .flat:
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(previewPurple)
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
        case .material:
          MaterialButtonEffect.roundedRect(
            baseColor: previewPurple,
            isPressed: pressed,
            seed: seed
          )
        }
      }
      .frame(width: 84, height: 64)

      Image(systemName: systemName)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.white)
    }
  }
}

private func previewCircleLabeled(
  title: String,
  systemName: String,
  seed: UInt64,
  style: PreviewStyle,
  pressed: Bool = false
) -> some View {
  VStack(spacing: 6) {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white.opacity(0.75))

    ZStack {
      Group {
        switch style {
        case .flat:
          Circle()
            .fill(previewPurple)
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        case .material:
          MaterialButtonEffect.circle(
            baseColor: previewPurple,
            isPressed: pressed,
            seed: seed
          )
        }
      }
      .frame(width: 86, height: 86)

      Image(systemName: systemName)
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(.white)
    }
  }
}
