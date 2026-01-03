//
//  AppSettings.swift
//  RockYou
//
//  Centralized app settings storage and sync.
//  Syncs to Watch via applicationContext when watch is paired.
//

import Foundation
import Combine

@MainActor
@Observable
final class AppSettings {
  static let shared = AppSettings()

  // MARK: - Power Button Delays

  var watchPowerDelay: TimeInterval? {
    get { loadDelay(key: "watchPowerDelay", defaultValue: 2.0) }
    set { setDelay(newValue, key: "watchPowerDelay") }
  }

  var phonePowerDelay: TimeInterval? {
    get { loadDelay(key: "phonePowerDelay", defaultValue: 2.0) }
    set { setDelay(newValue, key: "phonePowerDelay") }
  }

  // MARK: - Home Button Delays

  var watchHomeDelay: TimeInterval? {
    get { loadDelay(key: "watchHomeDelay", defaultValue: 2.0) }
    set { setDelay(newValue, key: "watchHomeDelay") }
  }

  var phoneHomeDelay: TimeInterval? {
    get { loadDelay(key: "phoneHomeDelay", defaultValue: 2.0) }
    set { setDelay(newValue, key: "phoneHomeDelay") }
  }

  // MARK: - App Channel Launch Delays (AppStrip)

  /// Watch app strip/app wheel: hold-to-launch delay (Off = tap-to-launch).
  var watchAppLaunchDelay: TimeInterval? {
    get { loadDelay(key: "watchAppLaunchDelay", defaultValue: 1.0) }
    set { setDelay(newValue, key: "watchAppLaunchDelay") }
  }

  /// Phone app strip: hold-to-launch delay (Off = tap-to-launch).
  var phoneAppLaunchDelay: TimeInterval? {
    get { loadDelay(key: "phoneAppLaunchDelay", defaultValue: 1.0) }
    set { setDelay(newValue, key: "phoneAppLaunchDelay") }
  }

  // MARK: - Launch Screen (Watch only)

  var watchLaunchScreen: LaunchScreen {
    get {
      if let raw = readDefaultsObject(key: "watchLaunchScreen") as? String,
         let screen = LaunchScreen(rawValue: raw) {
        return screen
      }
      return .home
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: "watchLaunchScreen")
      flushDefaultsIfDebug()
      syncToWatch()
    }
  }

  var watchAlwaysLaunchToMedia: Bool {
    get {
      if let value = readDefaultsObject(key: "watchAlwaysLaunchToMedia") as? Bool {
        return value
      }
      if let number = readDefaultsObject(key: "watchAlwaysLaunchToMedia") as? NSNumber {
        return number.boolValue
      }
      return false
    }
    set {
      UserDefaults.standard.set(newValue, forKey: "watchAlwaysLaunchToMedia")
      flushDefaultsIfDebug()
      syncToWatch()
    }
  }

  var watchConnectivitySettings: WCSyncedSettings {
    WCSyncedSettings(
      watchPowerDelay: watchPowerDelay ?? 0.0,
      watchHomeDelay: watchHomeDelay ?? 0.0,
      watchAppLaunchDelay: watchAppLaunchDelay ?? 0.0,
      watchLaunchScreen: watchLaunchScreen.rawValue,
      watchAlwaysLaunchToMedia: watchAlwaysLaunchToMedia
    )
  }

  // MARK: - Private Helpers

  func syncNow() {
    syncToWatch()
  }

  private func loadDelay(key: String, defaultValue: TimeInterval) -> TimeInterval? {
    guard let object = readDefaultsObject(key: key) else {
      return defaultValue
    }

    let value: TimeInterval
    if let doubleValue = object as? Double {
      value = doubleValue
    } else if let numberValue = object as? NSNumber {
      value = numberValue.doubleValue
    } else {
      return defaultValue
    }

    // Stored sentinel: 0 == Off (no sweep).
    if value <= 0 {
      return nil
    }
    return value
  }

  private func setDelay(_ value: TimeInterval?, key: String) {
    // Represent "Off" explicitly so it survives restarts.
    UserDefaults.standard.set(value ?? 0.0, forKey: key)
    flushDefaultsIfDebug()
    syncToWatch()
  }

  private func flushDefaultsIfDebug() {
    DebugBuild.flushUserDefaults()
  }

  private func readDefaultsObject(key: String) -> Any? {
    if let value = UserDefaults.standard.object(forKey: key) {
      return value
    }
    return PreferencesPlist.value(forKey: key)
  }

  private func syncToWatch() {
    AppSettingsPlatform.syncToWatch()
  }

  private init() {
    DebugBuild.syncCurrentAppPreferences()

    // Load initial values
    _ = watchPowerDelay
    _ = phonePowerDelay
    _ = watchHomeDelay
    _ = phoneHomeDelay
    _ = watchAppLaunchDelay
    _ = phoneAppLaunchDelay
    _ = watchLaunchScreen
    _ = watchAlwaysLaunchToMedia

    Log.debug(
      "Settings",
      "Loaded phonePowerDelay=\(phonePowerDelay ?? 0), phoneHomeDelay=\(phoneHomeDelay ?? 0), "
        + "phoneAppLaunchDelay=\(phoneAppLaunchDelay ?? 0), "
        + "watchPowerDelay=\(watchPowerDelay ?? 0), watchHomeDelay=\(watchHomeDelay ?? 0), "
        + "watchAppLaunchDelay=\(watchAppLaunchDelay ?? 0), "
        + "watchLaunchScreen=\(watchLaunchScreen.rawValue), watchAlwaysLaunchToMedia=\(watchAlwaysLaunchToMedia)"
    )
  }
}
