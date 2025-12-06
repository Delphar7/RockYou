import Foundation

enum AppCacheManagerPlatform {
  static var provider: RokuDataProvider { WatchProxyProvider.shared }

  static func iconDirectory(appSupport: URL) -> URL {
    appSupport.appendingPathComponent("AppIcons", isDirectory: true)
  }
}
