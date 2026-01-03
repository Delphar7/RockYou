import SwiftUI

enum RemoteControlPlatform {
  static func layoutMode(containerSize: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> LayoutMode {
    _ = horizontalSizeClass

    guard containerSize.width > 0 && containerSize.height > 0 else {
      return .landscapeSplit
    }
    // Drop the right pane when the window gets small.
    // Goals:
    // - Allow a true "mini remote" that can sit in a corner.
    // - Keep split layout for comfortably wide windows.
    let aspectRatio = containerSize.width / containerSize.height
    let minWidthForSplit: CGFloat = 760
    let minAspectForSplit: CGFloat = 1.05
    if containerSize.width < minWidthForSplit { return .portraitCompact }
    return aspectRatio >= minAspectForSplit ? .landscapeSplit : .portraitCompact
  }

  /// Baseline scale for macOS (normal window sizes).
  static var baseScaleFactor: CGFloat { 0.85 }

  /// Dynamic scaling for macOS so the remote can become a true “mini remote” in a tiny window.
  ///
  /// - For normal sizes, returns `baseScaleFactor`.
  /// - As the window height shrinks, we scale down smoothly.
  static func scaleFactor(containerSize: CGSize, layoutMode: LayoutMode) -> CGFloat {
    _ = layoutMode
    // Tuned by feel: around this height, we’re at “normal”.
    let referenceHeight: CGFloat = 720
    // Don’t let the UI go to zero; keep it usable.
    let minScale: CGFloat = 0.25

    guard containerSize.height > 0 else { return baseScaleFactor }
    let factor = min(1, containerSize.height / referenceHeight)
    return max(minScale, baseScaleFactor * factor)
  }

  /// When the remote shrinks below its baseline size, scale app-strip sizing to match.
  static func appStripScaleFactor(containerSize: CGSize, layoutMode: LayoutMode) -> CGFloat {
    let s = scaleFactor(containerSize: containerSize, layoutMode: layoutMode)
    return min(1, s / baseScaleFactor)
  }

  /// Tiny horizontal inset to avoid first/last icon clipping against the window edge in mini mode.
  static func appStripHorizontalInset(layoutMode: LayoutMode) -> CGFloat {
    layoutMode == .portraitCompact  ? 6 : 0
  }

  /// macOS: when we drop into the "portrait phone" layout (thin window), prefer a single-lane
  /// app strip so the transition is stable/predictable and not dependent on icon scaling.
  static func appStripLanesOverride(layoutMode: LayoutMode, direction: AppStripDirection) -> Int? {
    guard direction == .horizontal else { return nil }
    return layoutMode == .portraitCompact ? 1 : nil
  }

  /// Back-compat for call sites that haven’t been migrated to dynamic scaling.
  static var scaleFactor: CGFloat { baseScaleFactor }

  static func glowAnimationForegroundEnabled(scenePhase: ScenePhase, windowIsActive: Bool) -> Bool {
    _ = scenePhase
    // macOS: prefer window active state for "foreground window" correctness.
    return windowIsActive
  }

  static func shouldEnableActiveStatePolling(scenePhase: ScenePhase, selectedDeviceId: String?) -> Bool {
    _ = scenePhase
    // macOS: enable whenever a device is selected.
    return selectedDeviceId != nil
  }

  static var windowIsActiveDefault: Bool { true }

  // MARK: - Remote control layout tuning (macOS)

  static func remoteControlsTargetFraction(layoutMode: LayoutMode) -> CGFloat {
    // In split mode we want comfortable margins; in "mini remote" / portraitCompact
    // we want to use more of the available space.
    switch layoutMode {
    case .portraitCompact:
      return 0.95
    default:
      return 0.85
    }
  }

  static var remoteTopBarEdgePadding: CGFloat { 12 }

  /// macOS: avoid `scaleEffect` on interactive controls.
  ///
  /// On macOS, scaling a subtree containing `Button`s + custom `ButtonStyle`s can produce
  /// incorrect hit-testing (e.g. only part of the button responds) depending on window size
  /// and update timing. Instead, apply the fit scaling by multiplying the control metrics
  /// (`scaleFactor`) so the layout is truly resized (no transforms).
  ///
  /// Additionally, measure the control cluster at a fixed reference scale so the fit-scaling
  /// doesn't "cancel out" `RemoteControlPlatform.scaleFactor` (which is intentionally driven by
  /// window height).
  @ViewBuilder
  static func fitScaledControlCluster<Content: View, K: PreferenceKey>(
    content: (CGFloat) -> Content,
    scaleFactor: CGFloat,
    fitScale: CGFloat,
    measurePreferenceKey: K.Type
  ) -> some View where K.Value == CGSize {
    // `fitScale` is computed as `target / natural`, where `natural` is measured at `baseScaleFactor`.
    // Convert to an absolute scale (in the same units as `scaleFactor`) before applying.
    //
    // Important: we do NOT multiply `scaleFactor * fitScale` here. `scaleFactor` already encodes
    // macOS window-height-driven "mini remote" scaling; multiplying again causes over-scaling
    // (increasing padding as the window shrinks).
    let fitAbsoluteScale = fitScale * baseScaleFactor
    // Prefer the largest scale that fits (avoid "extra padding" as the window shrinks).
    // The global `scaleFactor` is still used elsewhere (e.g. AppStrip scaling), but the remote
    // control cluster should primarily obey this local fit calculation.
    content(fitAbsoluteScale)
      .background(
        content(baseScaleFactor)
          .background(
            GeometryReader { inner in
              Color.clear.preference(key: measurePreferenceKey, value: inner.size)
            }
          )
          .hidden()
      )
  }
}
