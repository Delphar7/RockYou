import SwiftUI

/// Centralized platform policy for `AppStripView` (watchOS).
enum AppStripPlatformPolicy {
  static var defaultSizing: AppStripSizing { .percent(15) }

  static var defaultFixedIconSize: (width: CGFloat, height: CGFloat) {
    switch defaultSizing {
    case .fixed(let w, let h):
      return (w ?? 72, h ?? 54)
    case .percent:
      // Percent-based sizing is handled elsewhere; choose a reasonable non-zero fallback.
      return (72, 54)
    }
  }

  static var showShadow: Bool { false }
  static var supportsGlowPulse: Bool { false }
  static var inactivityGatingEnabled: Bool { false }
  static var usesClickToLaunch: Bool { false }
  static var haloSafePaddingAlongScrollAxis: CGFloat { 0 }

  static func haloVerticalPadding(showLabels: Bool, scrollAxis: Axis.Set) -> (top: CGFloat, bottom: CGFloat) {
    _ = showLabels
    _ = scrollAxis
    return (0, 0)
  }
}
