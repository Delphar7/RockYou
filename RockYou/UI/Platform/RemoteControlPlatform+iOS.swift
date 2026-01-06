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

  static func glowAnimationForegroundEnabled(scenePhase: ScenePhase, windowIsActive: Bool) -> Bool {
    _ = windowIsActive
    return scenePhase == .active
  }

  static func shouldEnableActiveStatePolling(scenePhase: ScenePhase, selectedDeviceId: String?) -> Bool {
    scenePhase == .active && selectedDeviceId != nil
  }

  static var windowIsActiveDefault: Bool { true }

  static var remoteTopBarEdgePadding: CGFloat { 8 }

  /// iOS: Help is presented via a sheet (`SFSafariViewController`), so if Settings is already
  /// presented as a sheet we must dismiss it first.
  static var shouldDismissSettingsBeforePresentingHelp: Bool { true }
}
