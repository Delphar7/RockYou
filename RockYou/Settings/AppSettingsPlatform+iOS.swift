import Foundation
import WatchConnectivity

@MainActor
enum AppSettingsPlatform {
  static func syncToWatch(settings: [String: Any]) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired,
          session.isWatchAppInstalled
    else {
      return
    }

    do {
      try session.updateApplicationContext(["settings": settings])
    } catch {
      Log.warn("Settings", "Failed to sync settings to Watch: \(error.localizedDescription)")
    }
  }
}
