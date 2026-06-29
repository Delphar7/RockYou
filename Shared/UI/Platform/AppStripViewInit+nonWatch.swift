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
    // Delegate to the synthesized memberwise initializer rather than assigning each
    // stored property directly. A direct-assignment designated init in an extension forces
    // IRGen to materialize the struct field-by-field (including the @State/@ObservedObject/
    // @Environment backing storage), which crashes swift-frontend under the Xcode 27 /
    // Swift 6.4 toolchain. Delegating routes through the memberwise init, which codegens fine.
    self.init(
      apps: AppCacheManager.shared.apps(for: deviceId),
      deviceId: deviceId,
      onLaunch: onLaunch,
      direction: direction,
      lanes: lanes,
      sizing: sizing ?? AppStripSizing.defaultSizing(),
      showLabels: showLabels,
      appLaunchDelay: appLaunchDelay
    )
  }
}
