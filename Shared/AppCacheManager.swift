//
//  AppCacheManager.swift
//  RockYou (Shared - iOS/macOS)
//
//  MainActor façade for SwiftUI reads:
//  - Synchronous icon reads from disk (`iconImage(...)`) using PlatformImage's in-memory cache.
//  - Published state for UI.
//  - Delegates heavy work (network/disk maintenance) to AppCacheStore (actor).
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppCacheManager: ObservableObject {
  static let shared = AppCacheManager()

  @Published private(set) var appsByDevice: [String: [RokuApp]] = [:]
  @Published private(set) var iconVersion: Int = 0
  @Published private(set) var mruVersion: Int = 0

  private var appsFetchedAtByDevice: [String: TimeInterval] = [:]
  private var mruByDevice: [String: [String: TimeInterval]] = [:]
  private var iconLuminanceCache: [String: CGFloat] = [:]
  private let iconDirectory: URL?

  private init() {
    // UI needs to synchronously locate icons on disk; store does its own directory setup too.
    let fm = FileManager.default
    if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let dir = AppCacheManagerPlatform.iconDirectory(appSupport: appSupport)
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
      iconDirectory = dir
    } else {
      iconDirectory = nil
    }
  }

  // MARK: - Store bridging

  func applyStoreSnapshot(_ snapshot: AppCacheStore.Snapshot) {
    appsByDevice = snapshot.appsByDevice
    appsFetchedAtByDevice = snapshot.appsFetchedAtByDevice
    mruByDevice = snapshot.mruByDevice
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
    mruVersion &+= 1

    Task.detached(priority: .background) {
      await AppCacheStore.shared.setMRU(map, for: deviceId)
    }
  }

  func noteAppActivated(appId: String, deviceId: String, at timestamp: Date = Date()) {
    var map = mruByDevice[deviceId] ?? [:]
    let t = timestamp.timeIntervalSince1970
    if map[appId] == t { return }
    map[appId] = t
    mruByDevice[deviceId] = map
    mruVersion &+= 1

    Task.detached(priority: .background) {
      await AppCacheStore.shared.noteAppActivated(appId: appId, deviceId: deviceId, at: timestamp)
    }
  }

  // MARK: - Apps

  func apps(for deviceId: String) -> [RokuApp] {
    appsByDevice[deviceId] ?? []
  }

  func appsLastFetchedAt(for deviceId: String) -> Date? {
    guard let t = appsFetchedAtByDevice[deviceId] else { return nil }
    return Date(timeIntervalSince1970: t)
  }

  func hasApps(for deviceId: String) -> Bool {
    !(appsByDevice[deviceId]?.isEmpty ?? true)
  }

  func appsAreStale(for deviceId: String, maxAge: TimeInterval) -> Bool {
    guard let last = appsFetchedAtByDevice[deviceId] else { return true }
    return Date().timeIntervalSince1970 - last > maxAge
  }

  func fetchApps(for deviceId: String, deviceName: String? = nil) async {
    _ = deviceName
    _ = await AppCacheStore.shared.fetchApps(for: deviceId)
    applyStoreSnapshot(await AppCacheStore.shared.snapshot())
  }

  func requestForcedIconRefreshAfterNextAppsFetch(for deviceId: String, fallbackDelay: TimeInterval = 10) {
    Task.detached(priority: .background) {
      await AppCacheStore.shared.requestForcedIconRefreshAfterNextAppsFetch(
        for: deviceId, fallbackDelay: fallbackDelay
      )
    }
  }

  func prefetchIcons(appIds: [String], deviceId: String, visibleRange: Range<Int>, buffer: Int = 4) {
    Task.detached(priority: .background) {
      await AppCacheStore.shared.prefetchIcons(
        appIds: appIds, deviceId: deviceId, visibleRange: visibleRange, buffer: buffer
      )
    }
  }

  // MARK: - Icons (sync read for rendering)

  func iconImage(for appId: String, deviceId: String) -> Image? {
    guard let iconDirectory else { return nil }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDirectory.appendingPathComponent(app.iconFilename(for: deviceId))
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return PlatformImage.cachedContentsOfFile(fileURL.path)
  }

  func bumpIconVersion() {
    iconVersion &+= 1
    iconLuminanceCache.removeAll()
  }

  func bumpMRUVersion() { mruVersion &+= 1 }

  // MARK: - Icon edge luminance

  func iconEdgeLuminance(for appId: String, deviceId: String) -> CGFloat? {
    let key = "\(deviceId)_\(appId)"
    if let cached = iconLuminanceCache[key] { return cached }

    guard let iconDirectory else { return nil }
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDirectory.appendingPathComponent(app.iconFilename(for: deviceId))
    guard let native = PlatformImage.cachedNativeContentsOfFile(fileURL.path),
          let lum = PlatformImage.edgeLuminance(of: native) else { return nil }
    iconLuminanceCache[key] = lum
    return lum
  }
}
