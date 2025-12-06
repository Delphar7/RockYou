import Foundation

/// Centralized platform capability policy.
///
/// Intent: unify "Simulator limitations" checks behind one compile-time gate and keep call-sites
/// readable and consistent.
enum PlatformSecurityPolicy {
  /// True when running in a Simulator environment.
  static let isSimulator: Bool = {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }()

  /// Some Apple services require end-to-end encryption material (PCS/Manatee) that is not
  /// available in Simulator environments.
  static var supportsEndToEndEncryptedAPIs: Bool { !isSimulator }

  /// Human-readable reason string for UI/diagnostics.
  static var endToEndEncryptedAPIsUnavailableReason: String {
    "This feature requires end-to-end encrypted iCloud material (PCS/Manatee), which is not available on Simulator. Use a real device."
  }
}
