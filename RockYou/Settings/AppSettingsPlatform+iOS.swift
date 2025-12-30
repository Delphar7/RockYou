import Foundation
import WatchConnectivity

@MainActor
enum AppSettingsPlatform {
  static func syncToWatch() {
    // Keep all Watch applicationContext updates centralized in WatchConnectivityManager
    // so we don't duplicate payload shapes and keys.
    WatchConnectivityManager.shared.refreshWatchContext()
  }
}
