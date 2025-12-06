import SwiftUI

// Watch: Clean, minimal styling
extension View {
  func appButtonShadow(radius: CGFloat = 4, opacity: Double = AppOpacity.light) -> some View {
    self  // No-op on watchOS
  }

  func appButtonStroke<Shape: SwiftUI.Shape>(shape: Shape, opacity: Double = AppOpacity.standard) -> some View {
    self  // No-op on watchOS
  }
}
