//
//  WatchProxyProvider.swift
//  RockYou Watch App
//
//  Proxy implementation of RokuDataProvider.
//  Routes all requests through iPhone via WatchConnectivity.
//

import Foundation

/// Actor for async-safe management of pending icon requests
private actor PendingIconRequests {
  private var requests: [String: CheckedContinuation<Data?, Never>] = [:]

  func store(_ continuation: CheckedContinuation<Data?, Never>, for appId: String) {
    requests[appId] = continuation
  }

  func resume(appId: String, with data: Data?) -> Bool {
    if let continuation = requests.removeValue(forKey: appId) {
      continuation.resume(returning: data)
      return true
    }
    return false
  }
}

/// Proxy provider for watchOS - routes through iPhone
final class WatchProxyProvider: RokuDataProvider, @unchecked Sendable {
  static let shared = WatchProxyProvider()
  private init() {}

  private let pendingRequests = PendingIconRequests()

  func fetchApps(for deviceId: String) async -> [RokuApp] {
    // Apps are pushed from iPhone via ConnectivityManager, not pulled
    // Return cached apps from ConnectivityManager
    await MainActor.run {
      ConnectivityManager.shared.apps.map { info in
        RokuApp(id: info.id, name: info.name, type: info.type, version: nil)
      }
    }
  }

  func fetchAppIcon(appId: String, deviceId: String) async -> Data? {
    await withCheckedContinuation { continuation in
      Task {
        await pendingRequests.store(continuation, for: appId)

        // Request icon from iPhone
        await MainActor.run {
          ConnectivityManager.shared.requestIcon(appId: appId)
        }

        // Timeout after 10 seconds
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        let didTimeout = await pendingRequests.resume(appId: appId, with: nil)
        if didTimeout {
          Log.debug("Watch", "⏱️ Icon request timed out for appId=\(appId)")
        }
      }
    }
  }

  func launchApp(appId: String, deviceId: String) async -> Bool {
    await MainActor.run {
      ConnectivityManager.shared.launchApp(appId)
    }
    return true // Fire and forget - assume success
  }

  /// Called by ConnectivityManager when icon data arrives from iPhone
  func didReceiveIcon(appId: String, data: Data) {
    Task {
      let didResume = await pendingRequests.resume(appId: appId, with: data)
      if didResume {
        Log.debug("Watch", "✅ didReceiveIcon: resumed for appId=\(appId), \(data.count) bytes")
      } else {
        Log.debug("Watch", "didReceiveIcon: no pending request for appId=\(appId)")
      }
    }
  }
}
