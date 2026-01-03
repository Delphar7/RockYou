//
//  AppCacheManager+watchOS.swift
//  RockYou (Shared - watchOS)
//
//  watchOS implementation of AppCacheManager.
//  - Owns app list + icon disk cache locally on watch.
//  - Receives app lists + icons from iPhone via WatchConnectivity (see Watch app ConnectivityManager).
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppCacheManager: ObservableObject {
  static let shared = AppCacheManager()

  /// Apps keyed by device ID (serial number)
  @Published private(set) var appsByDevice: [String: [RokuApp]] = [:]

  /// Loading state per device
  @Published private(set) var loadingDevices: Set<String> = []

  /// Increments when icons are loaded - triggers UI refresh
  @Published private(set) var iconVersion: Int = 0

  /// Increments when MRU (app last-used timestamps) change - triggers UI refresh/sorting
  @Published private(set) var mruVersion: Int = 0

  // MARK: - Private

  private typealias IconMeta = AppCachePersistence.IconMeta
  private var iconDirectory: URL?

  /// Metadata for cached icons: "deviceId_appId" → meta
  private var iconMetas: [String: IconMeta] = [:]

  /// Last time the app list was fetched: deviceId → epoch seconds
  private var appsFetchedAtByDevice: [String: TimeInterval] = [:]

  /// App last-used timestamps (for AppStrip ordering): deviceId → (appId → epoch seconds)
  private var mruByDevice: [String: [String: TimeInterval]] = [:]

  /// Platform-specific data provider (watch uses WatchProxyProvider)
  private var provider: RokuDataProvider!

  /// When set for a deviceId, the next successful app-list fetch will trigger a forced icon refresh.
  /// Also has a fallback timer (used by manual "Refresh" flows that may not fetch apps immediately).
  private var pendingForcedIconRefreshDeviceIds: Set<String> = []
  private var forcedIconRefreshFallbackTasks: [String: Task<Void, Never>] = [:]

  private init() {
    provider = AppCacheManagerPlatform.provider

    appsByDevice = AppCachePersistence.loadAppsCache()
    appsFetchedAtByDevice = AppCachePersistence.loadAppsFetchedAt()
    mruByDevice = AppCachePersistence.loadMRU()
    iconMetas = AppCachePersistence.loadHashes()
    iconDirectory = AppCachePersistence.setupIconDirectory(
      makeIconDirectory: AppCacheManagerPlatform.iconDirectory(appSupport:)
    )

    if AppCachePersistence.ensureIconCacheSchema(iconDirectory: iconDirectory) {
      iconMetas.removeAll()
      AppCachePersistence.saveHashes(iconMetas)
      iconVersion &+= 1
    }
  }

  // MARK: - MRU (Last Used) API

  func lastUsedAt(appId: String, deviceId: String) -> Date? {
    guard let t = mruByDevice[deviceId]?[appId] else { return nil }
    return Date(timeIntervalSince1970: t)
  }

  func setMRU(_ map: [String: Date], for deviceId: String) {
    let encoded = map.mapValues { $0.timeIntervalSince1970 }
    if mruByDevice[deviceId] == encoded {
      return
    }
    mruByDevice[deviceId] = encoded
    saveMRU()
    mruVersion &+= 1
  }

  /// Record that an app was activated (used for MRU ordering in AppStrip).
  /// This is a purely-local update for responsiveness; CloudKit sync (if enabled) will reconcile.
  func noteAppActivated(appId: String, deviceId: String, at timestamp: Date = Date()) {
    var map = mruByDevice[deviceId] ?? [:]
    let t = timestamp.timeIntervalSince1970
    if map[appId] == t { return }
    map[appId] = t
    mruByDevice[deviceId] = map
    saveMRU()
    mruVersion &+= 1
  }

  private func saveMRU() {
    AppCachePersistence.saveMRU(mruByDevice)
  }

  // MARK: - Icon Hash API (watch↔phone sync)

  /// Get SHA-1 hash for a cached icon (empty string if not cached)
  func iconHash(for appId: String, deviceId: String) -> String {
    iconMetas["\(deviceId)_\(appId)"]?.hash ?? ""
  }

  /// Save icon with its SHA-1 hash (used when receiving from Phone)
  func saveIcon(
    appId: String,
    deviceId: String,
    data: Data,
    hash: String,
    originalPixelSize: CGSize? = nil
  ) {
    _ = originalPixelSize
    guard let iconDir = iconDirectory else { return }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))

    do {
      try data.write(to: fileURL)
      PlatformImage.purgeCache(for: fileURL.path)
      iconMetas["\(deviceId)_\(appId)"] = IconMeta(hash: hash)
      saveHashes()
      iconVersion &+= 1  // Trigger UI refresh
    } catch {
      Log.error("AppCache", "Failed to save icon \(appId): \(error.localizedDescription)")
    }
  }

  /// Trigger SwiftUI to re-render views showing icons (safe for external callers).
  func bumpIconVersion() { iconVersion &+= 1 }

  /// Trigger SwiftUI to re-render views that sort by MRU (safe for external callers).
  func bumpMRUVersion() { mruVersion &+= 1 }

  private func saveHashes() {
    AppCachePersistence.saveHashes(iconMetas)
  }

  private func saveAppsFetchedAt() {
    AppCachePersistence.saveAppsFetchedAt(appsFetchedAtByDevice)
  }

  // MARK: - Public API

  /// Get apps for a device (from cache)
  func apps(for deviceId: String) -> [RokuApp] {
    appsByDevice[deviceId] ?? []
  }

  func appsLastFetchedAt(for deviceId: String) -> Date? {
    guard let t = appsFetchedAtByDevice[deviceId] else { return nil }
    return Date(timeIntervalSince1970: t)
  }

  func appsAreStale(for deviceId: String, maxAge: TimeInterval) -> Bool {
    guard let last = appsFetchedAtByDevice[deviceId] else { return true }
    return Date().timeIntervalSince1970 - last > maxAge
  }

  /// Set apps for a device (used by Watch when receiving from Phone)
  func setApps(_ apps: [RokuApp], for deviceId: String) {
    appsByDevice[deviceId] = apps
    appsFetchedAtByDevice[deviceId] = Date().timeIntervalSince1970
    saveCache()
    saveAppsFetchedAt()
  }

  /// Check if we have apps cached for a device
  func hasApps(for deviceId: String) -> Bool {
    !(appsByDevice[deviceId]?.isEmpty ?? true)
  }

  /// Fetch and cache apps for a device (proxy provider on watch)
  func fetchApps(for deviceId: String, deviceName: String? = nil) async {
    let name = deviceName ?? deviceId
    Log.debug("AppCache", "📲 Fetching apps for \(name)")

    guard !loadingDevices.contains(deviceId) else { return }
    loadingDevices.insert(deviceId)
    defer { loadingDevices.remove(deviceId) }

    let apps = await provider.fetchApps(for: deviceId)
    guard !apps.isEmpty else { return }

    appsByDevice[deviceId] = apps
    appsFetchedAtByDevice[deviceId] = Date().timeIntervalSince1970
    saveCache()
    saveAppsFetchedAt()
  }

  /// Get icon for an app (from disk cache)
  func iconImage(for app: RokuApp, deviceId: String) -> Image? {
    guard let iconDir = iconDirectory else { return nil }
    let filename = app.iconFilename(for: deviceId)
    let fileURL = iconDir.appendingPathComponent(filename)
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return PlatformImage.cachedContentsOfFile(fileURL.path)
  }

  /// Get icon by app ID (convenience)
  func iconImage(for appId: String, deviceId: String) -> Image? {
    guard let app = appsByDevice[deviceId]?.first(where: { $0.id == appId }) else {
      let tempApp = RokuApp(id: appId, name: "", type: nil, version: nil)
      return iconImage(for: tempApp, deviceId: deviceId)
    }
    return iconImage(for: app, deviceId: deviceId)
  }

  /// Get raw icon data (for sending to phone / proxy coordination)
  func iconData(for appId: String, deviceId: String) -> Data? {
    guard let iconDir = iconDirectory else { return nil }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))
    return try? Data(contentsOf: fileURL)
  }

  func hasIcon(for appId: String, deviceId: String) -> Bool {
    guard let iconDir = iconDirectory else { return false }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))
    return FileManager.default.fileExists(atPath: fileURL.path)
  }

  func clearAllIcons() {
    AppCachePersistence.clearAllIconsOnDisk(iconDirectory: iconDirectory)
    PlatformImage.purgeAllCache()
    iconMetas.removeAll()
    saveHashes()
    iconVersion &+= 1
  }

  // MARK: - Persistence

  private func saveCache() {
    AppCachePersistence.saveAppsCache(appsByDevice)
  }
}
