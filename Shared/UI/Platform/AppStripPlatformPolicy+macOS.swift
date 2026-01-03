import SwiftUI

/// Centralized platform policy for `AppStripView` (macOS).
enum AppStripPlatformPolicy {
  static var defaultSizing: AppStripSizing { .fixed(iconWidth: 60, iconHeight: 45) }

  /// When icons get very small, multi-lane strips become cramped and harder to read.
  /// Below this icon height we collapse to a single lane.
  static var minIconHeightForMultiLane: CGFloat { 52 }

  static var defaultFixedIconSize: (width: CGFloat, height: CGFloat) {
    switch defaultSizing {
    case .fixed(let w, let h):
      return (w ?? 72, h ?? 54)
    case .percent:
      return (72, 54)
    }
  }

  static var showShadow: Bool { true }
  static var supportsGlowPulse: Bool { true }
  static var inactivityGatingEnabled: Bool { false }
  static var usesClickToLaunch: Bool { true }
  static var haloSafePaddingAlongScrollAxis: CGFloat { 12 }

  static func haloVerticalPadding(showLabels: Bool, scrollAxis: Axis.Set) -> (top: CGFloat, bottom: CGFloat) {
    guard scrollAxis == .horizontal else { return (0, 0) }
    let top: CGFloat = 14
    let bottom: CGFloat = showLabels ? 0 : 10
    return (top, bottom)
  }
}
