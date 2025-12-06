//
//  RokuDataProvider.swift
//  RockYou (Shared)
//
//  Protocol for fetching Roku data. Implemented differently per platform:
//  - iOS/macOS: DirectRokuProvider (network calls via RokuECPClient)
//  - watchOS: WatchProxyProvider (relay through iPhone via WatchConnectivity)
//

import Foundation

/// Abstract interface for fetching Roku device data
protocol RokuDataProvider: Sendable {
  /// Fetch installed apps for a device
  func fetchApps(for deviceId: String) async -> [RokuApp]

  /// Fetch app icon data
  func fetchAppIcon(appId: String, deviceId: String) async -> Data?

  /// Launch an app
  func launchApp(appId: String, deviceId: String) async -> Bool
}
