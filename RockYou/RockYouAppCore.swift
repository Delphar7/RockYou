import Foundation

enum RockYouAppCore {
  @MainActor
  static func initializeSharedServices() {
    // Initialize synchronously - don't use Task, as UI may access these before Task runs.
    _ = RokuDiscoveryService.shared

    // Initialize CloudKit household sync (pairings + MRU).
    CloudKitHouseholdStore.shared.startIfNeeded()

    // Kick off non-forced icon maintenance on startup (shared behavior across iOS + macOS).
    Task.detached(priority: .background) {
      await AppCacheManager.shared.refreshIconsIfNeededForAllCachedDevices()
    }
  }
}
