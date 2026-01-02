import SwiftUI

enum RemoteControlsSectionPlatform {
  static func targetFraction(layoutMode: LayoutMode) -> CGFloat {
    _ = layoutMode
    return 0.92
  }
}

enum RemoteTopBarPlatform {
  /// Symmetric left/right edge inset for top-bar buttons.
  static let edgePadding: CGFloat = 8
}
