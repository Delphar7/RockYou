//
//  AppCacheStore.swift
//  RockYou (Shared)
//
//  Background cache store for app lists + icons.
//  Owns disk I/O, hashing, and network fetches off the MainActor.
//

import Foundation

/// Background store that owns the cache state and all expensive operations (disk/network).
///
/// UI observes `AppCacheManager` (MainActor façade) which mirrors snapshots from this store.
actor AppCacheStore {
  static let shared = AppCacheStore()

  // MARK: - Snapshot

  struct Snapshot: Sendable {
    var appsByDevice: [String: [RokuApp]]
    var appsFetchedAtByDevice: [String: TimeInterval]
    var mruByDevice: [String: [String: TimeInterval]]
    var iconHashesByKey: [String: String]  // "\(deviceId)_\(appId)" -> sha1
  }

  // MARK: - Callbacks (UI + bridging)

  /// Called when icons changed on disk and UI should refresh.
  var onIconVersionBump: (@MainActor @Sendable () -> Void)?

  /// Called when MRU changes and UI should refresh (AppStrip sorting).
  var onMRUVersionBump: (@MainActor @Sendable () -> Void)?

  /// Called when an existing icon changes (hash update) and the phone should push to watch.
  var onIconHashChanged:
    (@Sendable (_ appId: String, _ deviceId: String, _ data: Data, _ hash: String) -> Void)?

  // MARK: - Wiring (from app bootstrap)

  func setOnIconVersionBump(_ callback: (@MainActor @Sendable () -> Void)?) {
    onIconVersionBump = callback
  }

  func setOnMRUVersionBump(_ callback: (@MainActor @Sendable () -> Void)?) {
    onMRUVersionBump = callback
  }

  func setOnIconHashChanged(
    _ callback: (
      @Sendable (_ appId: String, _ deviceId: String, _ data: Data, _ hash: String) -> Void
    )?
  ) {
    onIconHashChanged = callback
  }

  // MARK: - Private state (previously in AppCacheManager)

  private typealias IconMeta = AppCachePersistence.IconMeta

  private var appsByDevice: [String: [RokuApp]] = [:]
  private var appsFetchedAtByDevice: [String: TimeInterval] = [:]
  private var mruByDevice: [String: [String: TimeInterval]] = [:]
  private var iconMetas: [String: IconMeta] = [:]  // "\(deviceId)_\(appId)" -> meta

  private let provider: RokuDataProvider
  private var iconDirectory: URL?

  private var pendingForcedIconRefreshDeviceIds: Set<String> = []
  private var forcedIconRefreshFallbackTasks: [String: Task<Void, Never>] = [:]

  // Prevent double-fetches from multiple call sites.
  private var loadingDevices: Set<String> = []

  private init() {
    provider = AppCacheManagerPlatform.provider

    appsByDevice = AppCachePersistence.loadAppsCache()
    appsFetchedAtByDevice = AppCachePersistence.loadAppsFetchedAt()
    mruByDevice = AppCachePersistence.loadMRU()
    iconMetas = AppCachePersistence.loadHashes()

    iconDirectory = AppCachePersistence.setupIconDirectory(
      makeIconDirectory: AppCacheManagerPlatform.iconDirectory(appSupport:)
    )

    // Schema gate: if version changed, purge icons + metadata once at startup.
    if AppCachePersistence.ensureIconCacheSchema(iconDirectory: iconDirectory) {
      iconMetas.removeAll()
      AppCachePersistence.saveHashes(iconMetas)
      Task.detached { await AppCacheStore.shared.bumpIconVersion() }
    }
  }

  // MARK: - Snapshot API

  func snapshot() -> Snapshot {
    Snapshot(
      appsByDevice: appsByDevice,
      appsFetchedAtByDevice: appsFetchedAtByDevice,
      mruByDevice: mruByDevice,
      iconHashesByKey: iconMetas.mapValues { $0.hash }
    )
  }

  // MARK: - App list

  func fetchApps(for deviceId: String) async -> [RokuApp] {
    // Don't double-fetch
    if loadingDevices.contains(deviceId) { return appsByDevice[deviceId] ?? [] }
    loadingDevices.insert(deviceId)
    defer { loadingDevices.remove(deviceId) }

    let apps = await provider.fetchApps(for: deviceId)
    guard !apps.isEmpty else { return [] }

    appsByDevice[deviceId] = apps
    appsFetchedAtByDevice[deviceId] = Date().timeIntervalSince1970
    saveCache()
    saveAppsFetchedAt()

    // If a manual refresh requested a forced icon refresh, do it now that we have a fresh app list.
    if pendingForcedIconRefreshDeviceIds.contains(deviceId) {
      pendingForcedIconRefreshDeviceIds.remove(deviceId)
      forcedIconRefreshFallbackTasks[deviceId]?.cancel()
      forcedIconRefreshFallbackTasks[deviceId] = nil

      Task.detached(priority: .background) { [deviceId] in
        await AppCacheStore.shared.refreshAllIcons(for: deviceId)
      }
    } else {
      // Regular behavior: fetch icons only if missing SHA or TTL expired.
      Task.detached(priority: .background) { [apps, deviceId] in
        await AppCacheStore.shared.fetchMissingIcons(
          apps: apps, deviceId: deviceId, checkForChanges: false)
      }
    }

    return apps
  }

  // MARK: - MRU

  func lastUsedAt(appId: String, deviceId: String) -> Date? {
    guard let t = mruByDevice[deviceId]?[appId] else { return nil }
    return Date(timeIntervalSince1970: t)
  }

  func setMRU(_ map: [String: Date], for deviceId: String) {
    let encoded = map.mapValues { $0.timeIntervalSince1970 }
    if mruByDevice[deviceId] == encoded { return }
    mruByDevice[deviceId] = encoded
    saveMRU()
    let bump = onMRUVersionBump
    Task { @MainActor in bump?() }
  }

  func noteAppActivated(appId: String, deviceId: String, at timestamp: Date) {
    var map = mruByDevice[deviceId] ?? [:]
    let t = timestamp.timeIntervalSince1970
    if map[appId] == t { return }
    map[appId] = t
    mruByDevice[deviceId] = map
    saveMRU()
    let bump = onMRUVersionBump
    Task { @MainActor in bump?() }
  }

  // MARK: - Icons (read)

  func iconHash(for appId: String, deviceId: String) -> String {
    iconMetas["\(deviceId)_\(appId)"]?.hash ?? ""
  }

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

  // MARK: - Icons (maintenance)

  func refreshAllIcons(for deviceId: String) async {
    let apps = appsByDevice[deviceId] ?? []
    guard !apps.isEmpty else { return }
    await fetchMissingIcons(apps: apps, deviceId: deviceId, checkForChanges: true)
  }

  func refreshIconsIfNeeded(for deviceId: String) async {
    let apps = appsByDevice[deviceId] ?? []
    guard !apps.isEmpty else { return }
    await fetchMissingIcons(apps: apps, deviceId: deviceId, checkForChanges: false)
  }

  func refreshIconsIfNeededForAllCachedDevices() async {
    for deviceId in appsByDevice.keys {
      await refreshIconsIfNeeded(for: deviceId)
    }
  }

  func requestForcedIconRefreshAfterNextAppsFetch(
    for deviceId: String, fallbackDelay: TimeInterval = 10
  ) {
    pendingForcedIconRefreshDeviceIds.insert(deviceId)
    forcedIconRefreshFallbackTasks[deviceId]?.cancel()

    forcedIconRefreshFallbackTasks[deviceId] = Task.detached(priority: .background) { [deviceId] in
      let ns = UInt64(max(0, fallbackDelay) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: ns)
      await AppCacheStore.shared.forceFallbackRefreshIfStillPending(deviceId: deviceId)
    }
  }

  private func forceFallbackRefreshIfStillPending(deviceId: String) async {
    if pendingForcedIconRefreshDeviceIds.contains(deviceId) {
      pendingForcedIconRefreshDeviceIds.remove(deviceId)
      forcedIconRefreshFallbackTasks[deviceId] = nil
      await refreshAllIcons(for: deviceId)
    }
  }

  func prefetchIcons(appIds: [String], deviceId: String, visibleRange: Range<Int>, buffer: Int = 4)
  {
    let start = max(0, visibleRange.lowerBound - buffer)
    let end = min(appIds.count, visibleRange.upperBound + buffer)

    Task.detached(priority: .background) { [appIds, deviceId, start, end] in
      for i in start..<end {
        let appId = appIds[i]
        if await AppCacheStore.shared.hasIcon(for: appId, deviceId: deviceId) { continue }
        if let iconData = await AppCacheStore.shared.provider.fetchAppIcon(
          appId: appId, deviceId: deviceId)
        {
          await AppCacheStore.shared.saveIconToDisk(
            data: iconData, appId: appId, deviceId: deviceId)
          await AppCacheStore.shared.bumpIconVersion()
        }
      }
    }
  }

  // MARK: - Icons (write)

  func saveIcon(data: Data, appId: String, deviceId: String, hash: String) {
    guard let iconDir = iconDirectory else { return }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))

    do {
      try data.write(to: fileURL)
      PlatformImage.purgeCache(for: fileURL.path)
      iconMetas["\(deviceId)_\(appId)"] = IconMeta(hash: hash)
      saveHashes()
      Task.detached { await AppCacheStore.shared.bumpIconVersion() }
    } catch {
      Log.error("AppCache", "Failed to save icon \(appId): \(error.localizedDescription)")
    }
  }

  func saveIconAsync(data: Data, appId: String, deviceId: String) async {
    await saveIconToDisk(data: data, appId: appId, deviceId: deviceId)
  }

  private func saveIconToDisk(data: Data, appId: String, deviceId: String) async {
    guard let iconDir = iconDirectory else { return }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))

    do {
      try data.write(to: fileURL)
      PlatformImage.purgeCache(for: fileURL.path)

      let newHash = SHA1.hex(data)
      let key = "\(deviceId)_\(appId)"
      let oldHash = iconMetas[key]?.hash ?? ""
      let hashChanged = !oldHash.isEmpty && oldHash != newHash

      iconMetas[key] = IconMeta(hash: newHash)
      saveHashes()

      if hashChanged {
        onIconHashChanged?(appId, deviceId, data, newHash)
      }
      await bumpIconVersion()
    } catch {
      Log.error("AppCache", "Failed to save icon for appId=\(appId): \(error.localizedDescription)")
    }
  }

  func clearAllIcons() {
    guard let iconDir = iconDirectory else { return }
    let fm = FileManager.default

    if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
      for file in files where file.hasSuffix(".png") || file.hasSuffix(".jpg") {
        try? fm.removeItem(at: iconDir.appendingPathComponent(file))
      }
    }

    PlatformImage.purgeAllCache()
    iconMetas.removeAll()
    saveHashes()
    Task.detached { await AppCacheStore.shared.bumpIconVersion() }
  }

  func clearCache(for deviceId: String) {
    appsByDevice.removeValue(forKey: deviceId)
    appsFetchedAtByDevice.removeValue(forKey: deviceId)
    saveCache()
    saveAppsFetchedAt()

    guard let iconDir = iconDirectory else { return }
    let fm = FileManager.default
    let prefix = "\(deviceId)_"
    if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
      for file in files where file.hasPrefix(prefix) {
        try? fm.removeItem(at: iconDir.appendingPathComponent(file))
      }
    }

    iconMetas = iconMetas.filter { (key, _) in !key.hasPrefix(prefix) }
    saveHashes()
    Task.detached { await AppCacheStore.shared.bumpIconVersion() }
  }

  // MARK: - Internals

  private func bumpIconVersion() async {
    let bump = onIconVersionBump
    await MainActor.run { bump?() }
  }

  private func fetchMissingIcons(apps: [RokuApp], deviceId: String, checkForChanges: Bool) async {
    var iconsLoaded = 0
    for app in apps {
      let hasSHA = !iconHash(for: app.id, deviceId: deviceId).isEmpty
      let hasFile = hasIcon(for: app.id, deviceId: deviceId)
      let needsRefresh = iconNeedsRefresh(appId: app.id, deviceId: deviceId)

      if !checkForChanges && hasSHA && hasFile && !needsRefresh { continue }

      if let iconData = await provider.fetchAppIcon(appId: app.id, deviceId: deviceId) {
        await saveIconToDisk(data: iconData, appId: app.id, deviceId: deviceId)
        iconsLoaded += 1
        if iconsLoaded % 5 == 0 {
          await bumpIconVersion()
        }
      }
    }
    if iconsLoaded > 0 {
      await bumpIconVersion()
    }
  }

  private func iconNeedsRefresh(appId: String, deviceId: String) -> Bool {
    guard let iconDir = iconDirectory else { return true }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let modDate = attrs[.modificationDate] as? Date
    else {
      return true
    }
    let baseTTL: TimeInterval = 23 * 60 * 60
    let jitter = TimeInterval(Int.random(in: 0..<600))
    return Date().timeIntervalSince(modDate) > (baseTTL + jitter)
  }

  private func saveCache() {
    AppCachePersistence.saveAppsCache(appsByDevice)
  }

  private func saveAppsFetchedAt() {
    AppCachePersistence.saveAppsFetchedAt(appsFetchedAtByDevice)
  }

  private func saveMRU() {
    AppCachePersistence.saveMRU(mruByDevice)
  }

  private func saveHashes() {
    AppCachePersistence.saveHashes(iconMetas)
  }
}
