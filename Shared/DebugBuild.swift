import Foundation

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
}
