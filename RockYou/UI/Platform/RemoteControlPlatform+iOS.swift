import SwiftUI

enum RemoteControlPlatform {

  static func layoutMode(containerSize: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> LayoutMode {
    let isiPad = horizontalSizeClass == .regular
    let isPortrait = containerSize.height > containerSize.width

    if isiPad && isPortrait {
      return .portraitExpanded
    } else if !isiPad && !isPortrait {
      return .landscapeCompact
    } else if !isPortrait {
      return .landscapeSplit
    } else {
      return .portraitCompact
    }
  }

  static var baseScaleFactor: CGFloat { 0.98 }

  /// Back-compat for call sites that haven’t been migrated to dynamic scaling.
  static var scaleFactor: CGFloat { baseScaleFactor }

  /// iOS: keep scaling stable; we don’t want the remote shrinking with window size like macOS.
  static func scaleFactor(containerSize: CGSize, layoutMode: LayoutMode) -> CGFloat {
    _ = containerSize
    _ = layoutMode
    return baseScaleFactor
  }

  static func appStripScaleFactor(containerSize: CGSize, layoutMode: LayoutMode) -> CGFloat {
    _ = containerSize
    _ = layoutMode
    return 1
  }

  static func appStripHorizontalInset(layoutMode: LayoutMode) -> CGFloat {
    _ = layoutMode
    return 0
  }

  static func appStripLanesOverride(layoutMode: LayoutMode, direction: AppStripDirection) -> Int? {
    _ = layoutMode
    _ = direction
    return nil
  }

  // MARK: - "Tappability" policy knobs (iOS)
  //
  // These are intentionally platform-tunable: iOS needs bigger touch targets than macOS.

  /// Minimum acceptable cluster fit-scale before we start sacrificing AppStrip richness.
  static var minClusterScaleForStripLanePolicy: CGFloat { 0.82 }

  /// Hysteresis for switching 2↔1 lanes (mostly relevant on macOS window resizing, but safe here too).
  static var clusterScaleHysteresisForStripLanePolicy: CGFloat { 0.06 }

  /// Minimum usable AppStrip icon height on touch devices.
  /// (Below this, you will fat-finger apps.)
  static var minStripIconHeightForLanePolicy: CGFloat { 56 }

  static func glowAnimationForegroundEnabled(scenePhase: ScenePhase, windowIsActive: Bool) -> Bool {
    _ = windowIsActive
    return scenePhase == .active
  }

  static func shouldEnableActiveStatePolling(scenePhase: ScenePhase, selectedDeviceId: String?) -> Bool {
    scenePhase == .active && selectedDeviceId != nil
  }

  static var windowIsActiveDefault: Bool { true }

  static var remoteTopBarEdgePadding: CGFloat { 8 }

  /// Extra bottom clearance to avoid material/shadow chrome getting clipped when the global AppStrip
  /// is close to the controls (mostly noticeable on macOS; keep minimal on iOS).
  static var controlsBottomShadowClearance: CGFloat { 0 }

  /// iOS: Help is presented via a sheet (`SFSafariViewController`), so if Settings is already
  /// presented as a sheet we must dismiss it first.
  static var shouldDismissSettingsBeforePresentingHelp: Bool { true }

  // MARK: - Keyboard Presentation

  /// iOS freezes the containerSize while the keyboard is active to prevent layout jitter.
  static var freezesContainerSizeDuringKeyboard: Bool { true }

  /// iOS uses a ZStack with header overlay + ScrollView for keyboard support.
  /// macOS uses a simple VStack.
  static var usesScrollableShellForKeyboard: Bool { true }

  /// Bottom safe area padding for horizontal AppStrip to clear home indicator / grab handle.
  static func appStripSafeAreaBottomPadding(direction: AppStripDirection) -> CGFloat {
    direction == .horizontal ? 4 : 0
  }

  /// Presentation detents for keyboard entry sheet (iOS: none, uses safeAreaInset instead).
  static var keyboardEntryPresentationDetents: Set<PresentationDetent> { [] }
}
