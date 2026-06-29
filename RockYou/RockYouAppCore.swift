import Foundation

enum RockYouAppCore {
  @MainActor
  static func initializeSharedServices() {
    // Initialize synchronously - don't use Task, as UI may access these before Task runs.
    _ = RokuDiscoveryService.shared
    _ = AppCacheManager.shared

    // Initialize CloudKit household sync (pairings + MRU).
    CloudKitHouseholdStore.shared.startIfNeeded()

    // Route explicit in-app launches to CloudKit immediately (no wait for the active-app observer)
    // so the household converges on the same "most recent first" order. Observed active-app changes
    // (hardware remote / other members) funnel through the same `recordUse` path.
    AppCacheManager.shared.onExplicitLaunch = { appId, deviceId, at in
      CloudKitHouseholdStore.shared.recordUse(deviceId: deviceId, appId: appId, at: at, source: "launch")
    }

    // Kick off non-forced icon maintenance on startup (shared behavior across iOS + macOS).
    Task.detached(priority: .background) {
      // Route heavy icon maintenance off MainActor; only bounce to main for lightweight UI refresh.
      await AppCacheStore.shared.setOnIconVersionBump {
        AppCacheManager.shared.bumpIconVersion()
      }
      await AppCacheStore.shared.setOnMRUVersionBump {
        AppCacheManager.shared.bumpMRUVersion()
      }

      // Hydrate UI-facing caches from the store snapshot early (avoid reading caches on the render path).
      let snap = await AppCacheStore.shared.snapshot()
      await MainActor.run {
        AppCacheManager.shared.applyStoreSnapshot(snap)
      }

      await AppCacheStore.shared.refreshIconsIfNeededForAllCachedDevices()
    }
  }
}
