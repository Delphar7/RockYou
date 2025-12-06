import SwiftUI

// MARK: - Layout Mode

/// Unified layout mode that abstracts platform differences.
enum LayoutMode {
  /// Compact portrait layout (iPhone portrait, Mac thin window)
  case portraitCompact

  /// Split landscape layout (iPad landscape, Mac fat window)
  case landscapeSplit

  /// Compact landscape layout (iPhone landscape)
  case landscapeCompact

  /// Expanded portrait layout (iPad portrait)
  case portraitExpanded
}

// MARK: - App Strip Configuration

/// Configuration for AppStripView based on layout mode.
struct AppStripConfig {
  let isVisible: Bool
  let direction: AppStripDirection
  let lanes: Int
  let sizing: AppStripSizing?
  let showLabels: Bool
  let padding: EdgeInsets
  let position: AppStripPosition

  enum AppStripPosition {
    case bottom  // Full width at bottom
    case right  // Full height on right side
    case embedded  // Embedded in LandscapeiPhoneView
  }

  static func config(for mode: LayoutMode) -> AppStripConfig {
    switch mode {
    case .portraitCompact:
      return AppStripConfig(
        isVisible: true,
        direction: .horizontal,
        lanes: 2,
        sizing: nil,
        // iPhone portrait: labels off by default; wide Roku icons render their labels inside the tile.
        showLabels: false,
        padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        position: .bottom
      )

    case .landscapeSplit:
      return AppStripConfig(
        isVisible: true,
        direction: .horizontal,
        lanes: 1,
        sizing: .fixed(width: 96),
        showLabels: true,
        padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
        position: .bottom
      )

    case .landscapeCompact:
      return AppStripConfig(
        isVisible: true,
        direction: .vertical,
        lanes: 2,
        sizing: .fixed(width: 72),
        // Vertical strips can default to labels on.
        showLabels: true,
        padding: EdgeInsets(),
        position: .embedded
      )

    case .portraitExpanded:
      return AppStripConfig(
        isVisible: true,
        direction: .vertical,
        lanes: 1,
        sizing: .fixed(width: 96),
        // Vertical strips can default to labels on.
        showLabels: true,
        padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16),
        position: .right
      )
    }
  }
}
