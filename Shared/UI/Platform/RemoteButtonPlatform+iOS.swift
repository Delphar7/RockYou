import SwiftUI

/// Platform-specific rendering for `RemoteButton` (iOS).
enum RemoteButtonPlatform {
  static var defaultIconOnlyRectStyle: RemoteButtonStyle { .iosRect }

  static func makeBody(
    action: @escaping () -> Void,
    content: AnyView,
    style: RemoteButtonStyle,
    baseColor: Color?,
    materialSeed: UInt64
  ) -> AnyView {
    let materialBaseColor: Color = {
      // Important: do NOT use alpha (`.opacity`) to make “darker” variants here.
      // A translucent base fill interacts with our overlay/texture blend modes and can make the
      // face look washed out (“white mist”) against dark backgrounds.
      //
      // If we want darker variants later, prefer a true color adjustment (brightness/saturation),
      // not alpha.
      if let baseColor { return baseColor }
      // Baseline: all buttons default to `rokuPurple` unless a caller explicitly overrides.
      return rokuPurple
    }()

    if style.isCircle {
      return AnyView(
        Button(action: action) { content }
          .buttonStyle(MaterialButtonEffect.CircleStyle(baseColor: materialBaseColor, seed: materialSeed))
      )
    }

    return AnyView(
      Button(action: action) { content }
        .buttonStyle(
          MaterialButtonEffect.RoundedRectStyle(
            baseColor: materialBaseColor,
            seed: materialSeed,
            cornerRadius: style.cornerRadius
          )
        )
    )
  }

  static func decorateContent<Base: View>(base: Base, style: RemoteButtonStyle, baseColor: Color?, buttonShape: AnyShape)
    -> AnyView
  {
    _ = style
    _ = baseColor
    _ = buttonShape
    return AnyView(base)
  }
}
