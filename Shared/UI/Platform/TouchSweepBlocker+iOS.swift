import SwiftUI

/// iOS-only: registers a no-op sweep target so the window-level sweep router "hits" this view
/// instead of any sweepables behind it (e.g. AppStrip icons under a disabled control).
extension View {
  func platformTouchSweepBlocker(isActive: Bool, debugLabel: String) -> some View {
    background(
      Group {
        if isActive {
          SweepableTouchRouterInstaller(
            frame: .zero,
            suppressed: false,
            debugLabel: debugLabel,
            onBegan: {},
            onMoved: { _ in },
            onEnded: { _ in }
          )
        }
      }
    )
  }
}
