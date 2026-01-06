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
    layoutMode == .portraitCompact ? 6 : 0
  }

  static func appStripLanesOverride(layoutMode: LayoutMode, direction: AppStripDirection) -> Int? {
    _ = layoutMode
    _ = direction
    // Let the global lane policy (minClusterScale/minStripIconHeight + hysteresis) decide 2↔1.
    // This avoids a "stuck single-lane" strip when resizing back larger in portraitCompact.
    return nil
  }

  // MARK: - "Tappability" policy knobs (macOS)
  //
  // macOS can go smaller thanks to mouse precision; we still keep a sensible floor.

  /// Minimum acceptable cluster fit-scale before we start sacrificing AppStrip richness.
  static var minClusterScaleForStripLanePolicy: CGFloat { 0.60 }

  /// Hysteresis for switching 2↔1 lanes during window resizing.
  static var clusterScaleHysteresisForStripLanePolicy: CGFloat { 0.06 }

  /// Minimum usable AppStrip icon height on macOS (mouse makes smaller targets usable).
  static var minStripIconHeightForLanePolicy: CGFloat { 16 }

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

  static var remoteTopBarEdgePadding: CGFloat { 12 }

  /// Extra bottom clearance to avoid material/shadow chrome getting clipped when the global AppStrip
  /// is close to the controls (noticeable when the window height is tight).
  static var controlsBottomShadowClearance: CGFloat { 10 }

  static var shouldDismissSettingsBeforePresentingHelp: Bool { false }

  // MARK: - Keyboard Presentation

  /// macOS doesn't need to freeze containerSize during keyboard.
  static var freezesContainerSizeDuringKeyboard: Bool { false }

  /// macOS uses a simple VStack layout (no ScrollView wrapper for keyboard).
  static var usesScrollableShellForKeyboard: Bool { false }

  /// No safe area concerns on macOS.
  static func appStripSafeAreaBottomPadding(direction: AppStripDirection) -> CGFloat {
    _ = direction
    return 0
  }

  /// macOS keyboard entry uses a sheet with detents.
  static var keyboardEntryPresentationDetents: Set<PresentationDetent> {
    [.height(180), .medium]
  }
}
