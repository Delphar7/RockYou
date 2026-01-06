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

  static func config(for mode: LayoutMode) -> AppStripConfig {
    switch mode {
    case .portraitCompact:
      return AppStripConfig(
        isVisible: true,
        direction: .horizontal,
        lanes: 2,
        // Slightly smaller than the baseline strip so the portrait compact remote feels balanced.
        sizing: .fixed(width: 88),
        // iPhone portrait: labels off by default; wide Roku icons render their labels inside the tile.
        showLabels: false,
        // Keep a tiny bottom padding so the active-app glow halo isn’t clipped by the edge.
        padding: EdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 0)
      )

    case .landscapeSplit:
      return AppStripConfig(
        isVisible: true,
        direction: .horizontal,
        lanes: 1,
        sizing: .fixed(width: 96),
        showLabels: true,
        // Keep a little breathing room for the iPad grab handle, but don’t float the strip.
        padding: EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
      )

    case .landscapeCompact:
      return AppStripConfig(
        isVisible: true,
        direction: .vertical,
        lanes: 1,
        sizing: .fixed(width: 96),
        // Landscape compact: prioritize remote space; labels off by default.
        showLabels: false,
        // Give the vertical strip a small gutter so the remote buttons don't visually collide
        // with the strip (and so the outer edge isn't flush to the screen).
        padding: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
      )

    case .portraitExpanded:
      return AppStripConfig(
        isVisible: true,
        direction: .vertical,
        lanes: 1,
        sizing: .fixed(width: 96),
        // Vertical strips can default to labels on.
        showLabels: true,
        padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
      )
    }
  }
}
