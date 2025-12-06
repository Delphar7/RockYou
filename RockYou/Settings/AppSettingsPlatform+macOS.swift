import Foundation

@MainActor
enum AppSettingsPlatform {
  static func syncToWatch(settings: [String: Any]) {
    _ = settings
    // no-op on macOS
  }
}
