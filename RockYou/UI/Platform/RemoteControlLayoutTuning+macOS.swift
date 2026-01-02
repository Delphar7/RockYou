import SwiftUI

enum RemoteControlsSectionPlatform {
  static func targetFraction(layoutMode: LayoutMode) -> CGFloat {
    // In split mode we want comfortable margins; in "mini remote" / portraitCompact
    // we want to use more of the available space.
    switch layoutMode {
    case .portraitCompact:
      return 0.95
    default:
      return 0.85
    }
  }
}

enum RemoteTopBarPlatform {
  /// Symmetric left/right edge inset for top-bar buttons.
  static let edgePadding: CGFloat = 12
}
