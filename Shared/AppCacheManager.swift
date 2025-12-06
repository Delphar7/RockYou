//
//  AppCacheManager.swift
//  RockYou (Shared)
//
//  Manages cached app lists and icons per Roku device.
//  Icons are stored to disk, app lists to UserDefaults.
//  Works on all platforms - uses injected RokuDataProvider for network.
//

import Combine
import CommonCrypto
import Foundation
import SwiftUI

// MARK: - App Cache Manager

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

  private let appsKey = "com.rockyou.appcache"
  private let appsFetchedAtKey = "com.rockyou.appcache.fetchedat"
  private let hashesKey = "com.rockyou.iconhashes.v3"
  private let iconCacheSchemaKey = "com.rockyou.iconcache.schema"
  private let iconCacheSchemaVersion: Int = 3
  private var iconDirectory: URL?

  private struct IconMeta: Codable, Sendable {
    let hash: String
  }

  /// Metadata for cached icons: "deviceId_appId" → meta
  private var iconMetas: [String: IconMeta] = [:]

  /// Last time the app list was fetched: deviceId → epoch seconds
  private var appsFetchedAtByDevice: [String: TimeInterval] = [:]

  /// App last-used timestamps (for AppStrip ordering): deviceId → (appId → epoch seconds)
  private var mruByDevice: [String: [String: TimeInterval]] = [:]

  /// Platform-specific data provider (set during init)
  private var provider: RokuDataProvider!

  /// When set for a deviceId, the next successful app-list fetch will trigger a forced icon refresh.
  /// Also has a fallback timer (used by manual "Refresh" flows that may not fetch apps immediately).
  private var pendingForcedIconRefreshDeviceIds: Set<String> = []
  private var forcedIconRefreshFallbackTasks: [String: Task<Void, Never>] = [:]

  private init() {
    provider = AppCacheManagerPlatform.provider

    loadCache()
    loadAppsFetchedAt()
    loadMRU()
    loadHashes()
    setupIconDirectory()
    validateIconCacheSchema()
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

  private func loadMRU() {
    let key = "com.rockyou.appcache.mru.v1"
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode([String: [String: TimeInterval]].self, from: data)
    else { return }
    mruByDevice = decoded
  }

  private func saveMRU() {
    let key = "com.rockyou.appcache.mru.v1"
    if let data = try? JSONEncoder().encode(mruByDevice) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  // MARK: - Icon Hash API (for Watch↔Phone sync)

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
    guard let iconDir = iconDirectory else { return }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))

    do {
      try data.write(to: fileURL)
      iconMetas["\(deviceId)_\(appId)"] = IconMeta(hash: hash)
      saveHashes()
      iconVersion += 1  // Trigger UI refresh
      Log.debug("AppCache", "✅ Saved icon \(appId) with hash \(hash.prefix(8))...")
    } catch {
      Log.error("AppCache", "Failed to save icon \(appId): \(error.localizedDescription)")
    }
  }

  /// Compute SHA-1 hash of data
  static func sha1(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
      _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func loadHashes() {
    guard let data = UserDefaults.standard.data(forKey: hashesKey) else { return }
    do {
      iconMetas = try JSONDecoder().decode([String: IconMeta].self, from: data)
    } catch {
      // Stale/unknown cache shape: purge and start fresh.
      Log.warn(
        "AppCache",
        "Icon meta decode failed; purging icon cache (err=\(error.localizedDescription))")
      clearAllIcons()
    }
  }

  private func loadAppsFetchedAt() {
    if let data = UserDefaults.standard.data(forKey: appsFetchedAtKey),
       let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
      appsFetchedAtByDevice = decoded
    }
  }

  private func saveHashes() {
    if let data = try? JSONEncoder().encode(iconMetas) {
      UserDefaults.standard.set(data, forKey: hashesKey)
    }
  }

  private func saveAppsFetchedAt() {
    if let data = try? JSONEncoder().encode(appsFetchedAtByDevice) {
      UserDefaults.standard.set(data, forKey: appsFetchedAtKey)
    }
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

  /// Fetch and cache apps for a device
  func fetchApps(for deviceId: String, deviceName: String? = nil) async {
    let name = deviceName ?? deviceId
    Log.debug("AppCache", "📲 Fetching apps for \(name)")

    // Don't double-fetch
    guard !loadingDevices.contains(deviceId) else {
      Log.debug("AppCache", "⏳ Already loading apps for \(deviceId)")
      return
    }

    loadingDevices.insert(deviceId)
    defer { loadingDevices.remove(deviceId) }

    // Fetch app list via provider
    let apps = await provider.fetchApps(for: deviceId)
    guard !apps.isEmpty else {
      Log.warn("AppCache", "No apps returned for \(name)")
      return
    }

    Log.info("AppCache", "✅ Fetched \(apps.count) apps for \(name)")

    // Log app-type distribution (helps diagnose Roku metadata like `tvin` / `menu`).
    // Keep it compact: one line per fetch, plus a tiny sample for interesting types.
    do {
      var counts: [String: Int] = [:]
      for app in apps {
        let t = (app.type?.isEmpty == false) ? app.type! : "nil"
        counts[t, default: 0] += 1
      }
      let summary =
        counts
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")

      let tvinSample =
        apps
        .filter { $0.type == "tvin" }
        .prefix(4)
        .map { "\($0.id)('\($0.name)')" }
        .joined(separator: ", ")

      let menuSample =
        apps
        .filter { $0.type == "menu" }
        .prefix(3)
        .map { "\($0.id)('\($0.name)')" }
        .joined(separator: ", ")

      Log.debug("AppCache", "App types for \(name): \(summary)")
      if !tvinSample.isEmpty {
        Log.debug("AppCache", "tvin sample for \(name): \(tvinSample)")
      }
      if !menuSample.isEmpty {
        Log.debug("AppCache", "menu sample for \(name): \(menuSample)")
      }
    }

    // Update cache
    appsByDevice[deviceId] = apps
    appsFetchedAtByDevice[deviceId] = Date().timeIntervalSince1970
    saveCache()
    saveAppsFetchedAt()

    // If a manual refresh requested a forced icon refresh, do it now that we have a fresh app list.
    if pendingForcedIconRefreshDeviceIds.contains(deviceId) {
      pendingForcedIconRefreshDeviceIds.remove(deviceId)
      forcedIconRefreshFallbackTasks[deviceId]?.cancel()
      forcedIconRefreshFallbackTasks[deviceId] = nil

      Task.detached(priority: .background) {
        await self.refreshAllIcons(for: deviceId)
      }
    } else {
      // Regular behavior: fetch icons only if missing SHA (new apps) or TTL expired
    // Hash comparison happens at save time - detects changes and pushes to Watch
    Task.detached(priority: .background) {
      await self.fetchMissingIcons(apps: apps, deviceId: deviceId, checkForChanges: false)
      }
    }
  }

  /// Get icon for an app (from disk cache)
  func iconImage(for app: RokuApp, deviceId: String) -> Image? {
    guard let iconDir = iconDirectory else { return nil }
    let filename = app.iconFilename(for: deviceId)
    let fileURL = iconDir.appendingPathComponent(filename)

    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return PlatformSwiftUIImage.contentsOfFile(fileURL.path)
  }

  /// Get icon by app ID (convenience)
  func iconImage(for appId: String, deviceId: String) -> Image? {
    guard let app = appsByDevice[deviceId]?.first(where: { $0.id == appId }) else {
      // Create temporary app just for filename
      let tempApp = RokuApp(id: appId, name: "", type: nil, version: nil)
      return iconImage(for: tempApp, deviceId: deviceId)
    }
    return iconImage(for: app, deviceId: deviceId)
  }

  private func validateIconCacheSchema() {
    let current = UserDefaults.standard.integer(forKey: iconCacheSchemaKey)
    if current != iconCacheSchemaVersion {
      Log.info(
        "AppCache",
        "🧹 Icon cache schema changed (\(current) → \(iconCacheSchemaVersion)); purging icon cache")
      clearAllIcons()
      UserDefaults.standard.set(iconCacheSchemaVersion, forKey: iconCacheSchemaKey)
    }
  }

  /// Get raw icon data (for sending to watch)
  func iconData(for appId: String, deviceId: String) -> Data? {
    guard let iconDir = iconDirectory else { return nil }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))
    return try? Data(contentsOf: fileURL)
  }

  /// Check if icon exists on disk
  func hasIcon(for app: RokuApp, deviceId: String) -> Bool {
    guard let iconDir = iconDirectory else { return false }
    let filename = app.iconFilename(for: deviceId)
    let fileURL = iconDir.appendingPathComponent(filename)
    return FileManager.default.fileExists(atPath: fileURL.path)
  }

  /// Check if icon exists by app ID
  func hasIcon(for appId: String, deviceId: String) -> Bool {
    guard let iconDir = iconDirectory else { return false }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))
    return FileManager.default.fileExists(atPath: fileURL.path)
  }

  /// Check if icon needs refresh (older than ~23 hours with jitter)
  private func iconNeedsRefresh(for app: RokuApp, deviceId: String) -> Bool {
    guard let iconDir = iconDirectory else { return true }
    let filename = app.iconFilename(for: deviceId)
    let fileURL = iconDir.appendingPathComponent(filename)

    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
          let modDate = attrs[.modificationDate] as? Date else {
      return true  // Can't read attrs, treat as needing refresh
    }

    // TTL: 23 hours + random 0-600 seconds (spread refreshes over ~10 min window)
    let baseTTL: TimeInterval = 23 * 60 * 60  // 23 hours
    let jitter = TimeInterval(Int.random(in: 0..<600))  // 0-10 minutes
    let ttl = baseTTL + jitter

    let age = Date().timeIntervalSince(modDate)
    return age > ttl
  }

  // MARK: - Icon Fetching

  /// Fetch icons for apps.
  /// - checkForChanges=true: fetches ALL to detect hash changes
  /// - checkForChanges=false: only fetches if missing SHA or TTL expired
  private func fetchMissingIcons(apps: [RokuApp], deviceId: String, checkForChanges: Bool = false) async {
    var iconsLoaded = 0

    for app in apps {
      let hasSHA = !iconHash(for: app.id, deviceId: deviceId).isEmpty
      let hasFile = hasIcon(for: app, deviceId: deviceId)
      let needsRefresh = iconNeedsRefresh(for: app, deviceId: deviceId)

      // Skip if we have SHA and file and not expired (unless force checking)
      if !checkForChanges && hasSHA && hasFile && !needsRefresh {
        continue
      }

      // Fetch icon via provider
      if let iconData = await provider.fetchAppIcon(appId: app.id, deviceId: deviceId) {
        // saveIconToDisk will detect hash changes and trigger onIconHashChanged
        await saveIconToDisk(data: iconData, for: app, deviceId: deviceId)
        iconsLoaded += 1

        // Batch UI updates: refresh every 5 icons or at the end
        if iconsLoaded % 5 == 0 {
          await triggerIconRefresh()
        }
      }
    }

    // Final refresh if we loaded any icons
    if iconsLoaded > 0 {
      await triggerIconRefresh()
      Log.debug("AppCache", "✅ Loaded \(iconsLoaded) icons")
    }
  }

  /// Refresh all icons to check for changes (explicit refresh)
  func refreshAllIcons(for deviceId: String) async {
    let apps = appsByDevice[deviceId] ?? []
    guard !apps.isEmpty else { return }

    Log.debug("AppCache", "🔄 Refreshing all \(apps.count) icons for hash check")
    await fetchMissingIcons(apps: apps, deviceId: deviceId, checkForChanges: true)
  }

  /// Non-forced icon maintenance: refresh missing/expired icons for a device.
  func refreshIconsIfNeeded(for deviceId: String) async {
    let apps = appsByDevice[deviceId] ?? []
    guard !apps.isEmpty else { return }
    await fetchMissingIcons(apps: apps, deviceId: deviceId, checkForChanges: false)
  }

  /// Non-forced icon maintenance for all cached devices. Intended for app startup.
  func refreshIconsIfNeededForAllCachedDevices() async {
    for deviceId in appsByDevice.keys {
      await refreshIconsIfNeeded(for: deviceId)
    }
  }

  /// Request a one-shot forced icon refresh for a device after the next app-list fetch completes.
  /// If no app-list fetch happens soon, a fallback will force-refresh after `fallbackDelay`.
  func requestForcedIconRefreshAfterNextAppsFetch(
    for deviceId: String,
    fallbackDelay: TimeInterval = 10
  ) {
    pendingForcedIconRefreshDeviceIds.insert(deviceId)

    // Replace any existing fallback timer.
    forcedIconRefreshFallbackTasks[deviceId]?.cancel()
    forcedIconRefreshFallbackTasks[deviceId] = Task.detached(priority: .background) { [weak self] in
      let ns = UInt64(max(0, fallbackDelay) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      guard let self else { return }

      // If already satisfied (apps fetched), do nothing.
      let shouldForce: Bool = await MainActor.run {
        let pending = self.pendingForcedIconRefreshDeviceIds.contains(deviceId)
        if pending {
          self.pendingForcedIconRefreshDeviceIds.remove(deviceId)
          self.forcedIconRefreshFallbackTasks[deviceId] = nil
        }
        return pending
      }

      guard shouldForce else { return }
      await self.refreshAllIcons(for: deviceId)
    }
  }

  /// Prefetch icons for a visible range (for lazy loading)
  func prefetchIcons(appIds: [String], deviceId: String, visibleRange: Range<Int>, buffer: Int = 4) {
    let start = max(0, visibleRange.lowerBound - buffer)
    let end = min(appIds.count, visibleRange.upperBound + buffer)

    Task.detached(priority: .background) {
      for i in start..<end {
        let appId = appIds[i]

        // Skip if already cached
        if await self.hasIcon(for: appId, deviceId: deviceId) { continue }

        // Fetch via provider
        if let iconData = await self.provider.fetchAppIcon(appId: appId, deviceId: deviceId) {
          let app = RokuApp(id: appId, name: "", type: nil, version: nil)
          await self.saveIconToDisk(data: iconData, for: app, deviceId: deviceId)
          await self.triggerIconRefresh()
        }
      }
    }
  }

  /// Callback when icon hash changes (Phone uses this to push to Watch)
  var onIconHashChanged: ((_ appId: String, _ deviceId: String, _ data: Data, _ hash: String) -> Void)?

  private func saveIconToDisk(data: Data, for app: RokuApp, deviceId: String) async {
    guard let iconDir = iconDirectory else { return }
    let filename = app.iconFilename(for: deviceId)
    let fileURL = iconDir.appendingPathComponent(filename)

    do {
      try data.write(to: fileURL)
      // Compute and store hash when saving
      let newHash = Self.sha1(data)
      let key = "\(deviceId)_\(app.id)"
      let oldHash = iconMetas[key]?.hash ?? ""

      // Check if hash changed
      let hashChanged = !oldHash.isEmpty && oldHash != newHash

      // Store hash; original pixel size can be derived later from the on-disk image if needed.
      iconMetas[key] = IconMeta(hash: newHash)
      saveHashes()

      // Notify if hash changed (icon updated)
      if hashChanged {
        Log.info("AppCache", "🔄 Icon hash changed for \(app.id): \(oldHash.prefix(8))... → \(newHash.prefix(8))...")
        onIconHashChanged?(app.id, deviceId, data, newHash)
      }
    } catch {
      Log.error("AppCache", "Failed to save icon for \(app.name): \(error.localizedDescription)")
    }
  }

  /// Public async save for when Phone fetches from Roku
  func saveIconAsync(data: Data, for app: RokuApp, deviceId: String) async {
    await saveIconToDisk(data: data, for: app, deviceId: deviceId)
  }

  /// Save icon data directly (legacy - computes hash automatically)
  func saveIcon(appId: String, deviceId: String, data: Data) {
    let hash = Self.sha1(data)
    saveIcon(appId: appId, deviceId: deviceId, data: data, hash: hash)
  }

  /// Trigger SwiftUI to re-render views showing icons
  private func triggerIconRefresh() async {
    await MainActor.run {
      iconVersion += 1
    }
  }

  // MARK: - Persistence

  private func setupIconDirectory() {
    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      Log.error("AppCache", "Could not find applicationSupportDirectory")
      return
    }
    let iconDir = AppCacheManagerPlatform.iconDirectory(appSupport: appSupport)

    do {
      try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
      iconDirectory = iconDir

      // Log cached icon count on startup
      if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
        let iconCount = files.filter { $0.hasSuffix(".png") || $0.hasSuffix(".jpg") }.count
        Log.info("AppCache", "📁 Icon directory: \(iconDir.path) (\(iconCount) cached icons)")
      }
    } catch {
      Log.error("AppCache", "Failed to create icon directory: \(error.localizedDescription)")
    }
  }

  private func loadCache() {
    guard let data = UserDefaults.standard.data(forKey: appsKey),
          let cached = try? JSONDecoder().decode([String: [RokuApp]].self, from: data)
    else { return }

    appsByDevice = cached
  }

  private func saveCache() {
    guard let data = try? JSONEncoder().encode(appsByDevice) else { return }
    UserDefaults.standard.set(data, forKey: appsKey)
  }

  /// Clear all cached data for a device
  func clearCache(for deviceId: String) {
    appsByDevice.removeValue(forKey: deviceId)
    appsFetchedAtByDevice.removeValue(forKey: deviceId)
    saveCache()
    saveAppsFetchedAt()

    // Remove icons
    guard let iconDir = iconDirectory else { return }
    let fm = FileManager.default
    let prefix = "\(deviceId)_"

    if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
      for file in files where file.hasPrefix(prefix) {
        try? fm.removeItem(at: iconDir.appendingPathComponent(file))
      }
    }

    // Remove hashes/metadata for this device too.
    iconMetas = iconMetas.filter { (key, _) in
      !key.hasPrefix(prefix)
    }
    saveHashes()
  }

  /// Clear ALL icon cache (force re-fetch)
  func clearAllIcons() {
    guard let iconDir = iconDirectory else { return }
    let fm = FileManager.default

    if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
      var count = 0
      for file in files where file.hasSuffix(".png") || file.hasSuffix(".jpg") {
        try? fm.removeItem(at: iconDir.appendingPathComponent(file))
        count += 1
      }
      Log.info("AppCache", "🗑️ Cleared \(count) cached icons")
    }

    // Also clear hashes/metadata
    iconMetas.removeAll()
    saveHashes()

    iconVersion += 1  // Trigger UI refresh
  }
}
