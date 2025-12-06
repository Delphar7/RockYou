import SwiftUI

/// Platform-specific rendering for `RemoteButton` (macOS).
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
      // See iOS implementation for rationale: avoid alpha-based darkening here.
      if let baseColor { return baseColor }
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
