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

  // MARK: - Remote control layout tuning (iOS)

  static func remoteControlsTargetFraction(layoutMode: LayoutMode) -> CGFloat {
    _ = layoutMode
    return 0.92
  }

  static var remoteTopBarEdgePadding: CGFloat { 8 }

  /// iOS: use transform scaling for fit; hit-testing remains correct.
  @ViewBuilder
  static func fitScaledControlCluster<Content: View, K: PreferenceKey>(
    content: (CGFloat) -> Content,
    scaleFactor: CGFloat,
    fitScale: CGFloat,
    measurePreferenceKey: K.Type
  ) -> some View where K.Value == CGSize {
    content(scaleFactor)
      .background(
        GeometryReader { inner in
          Color.clear.preference(key: measurePreferenceKey, value: inner.size)
        }
      )
      .scaleEffect(fitScale, anchor: .center)
  }
}
