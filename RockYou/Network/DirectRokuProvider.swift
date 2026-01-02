//
//  DirectRokuProvider.swift
//  RockYou (iOS/macOS)
//
//  Direct implementation of RokuDataProvider using RokuECPClient.
//  Makes network calls directly to Roku devices.
//

import Foundation

/// Direct network provider for iOS/macOS - talks to Roku devices via ECP
final class DirectRokuProvider: RokuDataProvider, @unchecked Sendable {
  static let shared = DirectRokuProvider()
  private init() {}

  func fetchApps(for deviceId: String) async -> [RokuApp] {
      let device = await MainActor.run {
        RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
      }
      guard let device else {
      return []
    }
    return await RokuECPClient.shared.fetchApps(for: device)
  }

  func fetchAppIcon(appId: String, deviceId: String) async -> Data? {
      let device = await MainActor.run {
        RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
      }
      guard let device else {
      return nil
    }
    return await RokuECPClient.shared.fetchAppIcon(appId: appId, device: device)
  }

  func launchApp(appId: String, deviceId: String) async -> Bool {
      let device = await MainActor.run {
        RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
      }
      guard let device else {
      return false
    }
    return await RokuECPClient.shared.launchApp(appId: appId, device: device)
  }
}
