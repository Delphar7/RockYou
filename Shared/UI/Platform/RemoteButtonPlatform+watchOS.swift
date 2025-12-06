import SwiftUI

/// Platform-specific rendering for `RemoteButton` (watchOS).
enum RemoteButtonPlatform {
  static var defaultIconOnlyRectStyle: RemoteButtonStyle { .rect }

  static func makeBody(
    action: @escaping () -> Void,
    content: AnyView,
    style: RemoteButtonStyle,
    baseColor: Color?,
    materialSeed: UInt64
  ) -> AnyView {
    _ = style
    _ = baseColor
    _ = materialSeed

    return AnyView(
      Button(action: action) { content }
        .buttonStyle(.swipeAware)
    )
  }

  static func decorateContent<Base: View>(base: Base, style: RemoteButtonStyle, baseColor: Color?, buttonShape: AnyShape)
    -> AnyView
  {
    _ = style

    // Keep watch simple/legible; avoid alpha-darkening for consistency with the material approach.
    return AnyView(
      base
        .background((baseColor ?? rokuPurple))
        .clipShape(buttonShape)
        .appButtonStroke(shape: buttonShape, opacity: 0.5)
    )
  }
}
