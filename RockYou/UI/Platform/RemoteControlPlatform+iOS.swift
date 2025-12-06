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

  static var scaleFactor: CGFloat { 1.0 }

  static func glowAnimationForegroundEnabled(scenePhase: ScenePhase, windowIsActive: Bool) -> Bool {
    _ = windowIsActive
    return scenePhase == .active
  }

  static func shouldEnableActiveStatePolling(scenePhase: ScenePhase, selectedDeviceId: String?) -> Bool {
    scenePhase == .active && selectedDeviceId != nil
  }

  static var windowIsActiveDefault: Bool { true }
}
