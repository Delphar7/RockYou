import SwiftUI

/// Centralized platform policy for `AppStripView` (iOS).
enum AppStripPlatformPolicy {
  static var defaultSizing: AppStripSizing { .fixed(iconWidth: 72, iconHeight: 54) }

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
  static var inactivityGatingEnabled: Bool { true }
  static var usesClickToLaunch: Bool { false }
  static var haloSafePaddingAlongScrollAxis: CGFloat { 12 }

  static func haloVerticalPadding(showLabels: Bool, scrollAxis: Axis.Set) -> (top: CGFloat, bottom: CGFloat) {
    _ = showLabels
    _ = scrollAxis
    return (0, 0)
  }
}
