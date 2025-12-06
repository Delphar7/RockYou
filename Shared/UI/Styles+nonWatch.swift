import SwiftUI

// iOS/macOS: Shadows and strokes for depth
struct AppButtonShadow: ViewModifier {
  let radius: CGFloat
  let opacity: Double

  func body(content: Content) -> some View {
    content.shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: radius / 2)
  }
}

struct AppButtonStroke<S: SwiftUI.Shape>: ViewModifier {
  let shape: S
  let opacity: Double

  func body(content: Content) -> some View {
    content.overlay(shape.stroke(Color.white.opacity(opacity), lineWidth: 1))
  }
}

extension View {
  func appButtonShadow(radius: CGFloat = 4, opacity: Double = AppOpacity.light) -> some View {
    modifier(AppButtonShadow(radius: radius, opacity: opacity))
  }

  func appButtonStroke<Shape: SwiftUI.Shape>(shape: Shape, opacity: Double = AppOpacity.standard) -> some View {
    modifier(AppButtonStroke(shape: shape, opacity: opacity))
  }
}
