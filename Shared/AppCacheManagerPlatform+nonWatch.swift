import Foundation

enum AppCacheManagerPlatform {
  static var provider: RokuDataProvider { DirectRokuProvider.shared }

  static func iconDirectory(appSupport: URL) -> URL {
    appSupport.appendingPathComponent("RockYou/AppIcons", isDirectory: true)
  }
}
