import SwiftUI

/// Rectangular button for navigation/utility functions (iOS style)
struct TopKeyButton: View {
  let systemName: String
  var width: CGFloat = 54
  var height: CGFloat = 44
  /// If nil, the glyph size is derived from `height` so it scales with the button.
  var fontSize: CGFloat? = nil
  var cornerRadius: CGFloat = 12
  var baseColor: Color? = nil
  let action: () -> Void

  var body: some View {
    let computedFontSize = fontSize ?? (height * 0.38)
    RemoteButton(
      icon: systemName,
      action: action,
      style: .custom(
        width: width,
        height: height,
        isCircle: false,
        iconSize: computedFontSize,
        cornerRadius: cornerRadius
      ),
      baseColor: baseColor
    )
  }
}

/// Circular button for D-pad and transport controls (iOS style)
struct CircleKeyButton: View {
  let systemName: String
  var size: CGFloat = 64
  var baseColor: Color? = nil
  let action: () -> Void

  var body: some View {
    RemoteButton(icon: systemName, action: action, style: .iosCircle(size: size), baseColor: baseColor)
  }
}

/// Central "OK" button (iOS style)
struct OKKeyButton: View {
  var size: CGFloat = 84
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("OK")
        .font(.system(size: size * 0.32, weight: .heavy))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(rokuPurple)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(AppOpacity.standard), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .appButtonShadow(radius: 8, opacity: 0.2)
  }
}
