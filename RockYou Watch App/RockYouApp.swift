//
//  RockYouApp.swift
//  RockYou Watch App
//
//  Created by Delphar Se7en on 11/10/25.
//

import SwiftUI

@main
struct RockYou_Watch_AppApp: App {

    private static let cacheVersion = "iconCacheV3_sha1"  // Bump to force re-sync

    init() {
        // Initialize connectivity as early as possible
        _ = ConnectivityManager.shared

        // One-time migration: clear icons without hashes to force hash-based re-sync
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.cacheVersion) {
            Task { @MainActor in
                AppCacheManager.shared.clearAllIcons()
                defaults.set(true, forKey: Self.cacheVersion)
                Log.info("Watch", "🔄 Cleared icon cache for SHA-1 hash migration")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
