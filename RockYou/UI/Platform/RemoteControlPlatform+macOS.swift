import SwiftUI

enum RemoteControlPlatform {
  static func layoutMode(containerSize: CGSize, horizontalSizeClass: UserInterfaceSizeClass?) -> LayoutMode {
    _ = horizontalSizeClass

    guard containerSize.width > 0 && containerSize.height > 0 else {
      return .landscapeSplit
    }
    let aspectRatio = containerSize.width / containerSize.height
    return aspectRatio >= 9.0 / 12.0 ? .landscapeSplit : .portraitCompact
  }

  static var scaleFactor: CGFloat { 0.85 }

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
}
