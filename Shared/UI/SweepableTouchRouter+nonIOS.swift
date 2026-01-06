#if !os(iOS)
import SwiftUI

// MARK: - No-op stubs for non-iOS platforms

extension View {
  /// No-op on non-iOS: sweepable touch router only exists on iOS.
  func sweepBlockingZone() -> some View {
    self
  }
}
#endif
