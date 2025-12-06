import SwiftUI

extension View {
  /// iOS implementation: no-op. (macOS draws the remote surface chrome.)
  func platformRemoteSurface(isActive: Bool) -> some View {
    _ = isActive
    return self
  }
}
