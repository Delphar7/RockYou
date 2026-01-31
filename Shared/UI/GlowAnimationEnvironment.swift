import SwiftUI

// MARK: - Glow animation gating (shared)
//
// AppIconWithLabel uses these environment values to decide whether to run periodic glow animations.
// - On watchOS: keep defaults (disabled).
// - On iOS: gate on scenePhase + user interaction timestamp.
// - On macOS: gate on window focus (controlActiveState) and scenePhase.

private struct GlowAnimationForegroundEnabledKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

private struct GlowAnimationLastUserInteractionAtKey: EnvironmentKey {
  static let defaultValue: Date = .distantPast
}

private struct GlowShimmerPhaseKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  /// True when the app/window is considered "foreground" for glow animations.
  var glowAnimationForegroundEnabled: Bool {
    get { self[GlowAnimationForegroundEnabledKey.self] }
    set { self[GlowAnimationForegroundEnabledKey.self] = newValue }
  }

  /// Timestamp of the last user interaction (touch/gesture) observed by the app.
  /// iOS-only: set via a lightweight interaction observer; other platforms can leave default.
  var glowAnimationLastUserInteractionAt: Date {
    get { self[GlowAnimationLastUserInteractionAtKey.self] }
    set { self[GlowAnimationLastUserInteractionAtKey.self] = newValue }
  }

  /// Linear sweep phase (0…1) for the active-app shimmer effect.
  /// Driven by the same pulse loop that animates `glowPulseFactor`.
  var glowShimmerPhase: CGFloat {
    get { self[GlowShimmerPhaseKey.self] }
    set { self[GlowShimmerPhaseKey.self] = newValue }
  }
}
