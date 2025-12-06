import SwiftUI

extension AppStripView {
  /// Convenience initializer that fetches apps from cache.
  init(
    deviceId: String,
    direction: AppStripDirection = .horizontal,
    lanes: Int = 1,
    sizing: AppStripSizing? = nil,
    showLabels: Bool = true,
    appLaunchDelay: TimeInterval? = 1.0,
    onLaunch: @escaping (RokuApp) -> Void
  ) {
    self.apps = AppCacheManager.shared.apps(for: deviceId)
    self.deviceId = deviceId
    self.direction = direction
    self.lanes = lanes
    self.sizing = sizing ?? AppStripSizing.defaultSizing()
    self.showLabels = showLabels
    self.appLaunchDelay = appLaunchDelay
    self.onLaunch = onLaunch
  }
}
