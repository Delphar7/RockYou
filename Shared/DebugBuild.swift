import Foundation
import CoreFoundation

/// Centralized debug-build gates so we can avoid sprinkling `#if DEBUG` across the codebase.
enum DebugBuild {
  static var isEnabled: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }

  /// Runs `work` only in Debug builds.
  static func run(_ work: () -> Void) {
    #if DEBUG
      work()
    #endif
  }

  /// In some simulator install flows `cfprefsd` can briefly serve stale values.
  /// This forces a sync for the current app's preferences domain (debug-only).
  static func syncCurrentAppPreferences() {
    run { CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication) }
  }

  /// Flush `UserDefaults` to disk (debug-only).
  static func flushUserDefaults() {
    run { UserDefaults.standard.synchronize() }
  }
}
