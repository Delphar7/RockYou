import Foundation

@MainActor
@Observable
final class WatchAppSettings {
  static let shared = WatchAppSettings()

  private init() {}

  var watchPowerDelay: TimeInterval? {
    get { loadDelay(key: "watchPowerDelay") }
    set { setDelay(newValue, key: "watchPowerDelay") }
  }

  var watchHomeDelay: TimeInterval? {
    get { loadDelay(key: "watchHomeDelay") }
    set { setDelay(newValue, key: "watchHomeDelay") }
  }

  // MARK: - App Channel Launch Delay (AppStrip)

  /// Watch app strip/app wheel: hold-to-launch delay (Off = tap-to-launch).
  var watchAppLaunchDelay: TimeInterval? {
    get { loadDelay(key: "watchAppLaunchDelay", defaultValue: 1.0) }
    set { setDelay(newValue, key: "watchAppLaunchDelay") }
  }

  var watchLaunchScreen: LaunchScreen {
    get {
      if let raw = UserDefaults.standard.string(forKey: "watchLaunchScreen"),
         let screen = LaunchScreen(rawValue: raw) {
        return screen
      }
      return .home
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "watchLaunchScreen")
    }
  }

  var watchAlwaysLaunchToMedia: Bool {
    get { UserDefaults.standard.bool(forKey: "watchAlwaysLaunchToMedia") }
    set { UserDefaults.standard.set(newValue, forKey: "watchAlwaysLaunchToMedia") }
  }

  func applySyncedSettings(_ settings: WCSyncedSettings) {
    watchPowerDelay = settings.watchPowerDelay <= 0 ? nil : settings.watchPowerDelay
    watchHomeDelay = settings.watchHomeDelay <= 0 ? nil : settings.watchHomeDelay
    watchAppLaunchDelay = settings.watchAppLaunchDelay <= 0 ? nil : settings.watchAppLaunchDelay

    if let screen = LaunchScreen(rawValue: settings.watchLaunchScreen) {
      watchLaunchScreen = screen
    }
    watchAlwaysLaunchToMedia = settings.watchAlwaysLaunchToMedia
  }

  private func loadDelay(key: String) -> TimeInterval? {
    loadDelay(key: key, defaultValue: 2.0)
  }

  private func loadDelay(key: String, defaultValue: TimeInterval) -> TimeInterval? {
    guard let object = UserDefaults.standard.object(forKey: key) else { return defaultValue }
    let value: TimeInterval
    if let doubleValue = object as? Double {
      value = doubleValue
    } else if let numberValue = object as? NSNumber {
      value = numberValue.doubleValue
    } else {
      return defaultValue
    }
    return value <= 0 ? nil : value
  }

  private func setDelay(_ value: TimeInterval?, key: String) {
    UserDefaults.standard.set(value ?? 0.0, forKey: key)
  }
}
