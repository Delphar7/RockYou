import Foundation

enum AppCachePersistence {
  enum Keys {
    static let apps = "com.rockyou.appcache"
    static let appsFetchedAt = "com.rockyou.appcache.fetchedat"
    static let hashes = "com.rockyou.iconhashes.v3"
    static let mru = "com.rockyou.appcache.mru.v1"
    static let iconCacheSchema = "com.rockyou.iconcache.schema"

    /// Bump when on-disk icon layout/meaning changes.
    static let iconCacheSchemaVersion: Int = 3
  }

  struct IconMeta: Codable, Sendable {
    let hash: String
  }

  // MARK: - Icon directory

  static func setupIconDirectory(makeIconDirectory: (_ appSupport: URL) -> URL) -> URL? {
    let fm = FileManager.default
    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      Log.error("AppCache", "Could not find applicationSupportDirectory")
      return nil
    }

    let iconDir = makeIconDirectory(appSupport)
    do {
      try fm.createDirectory(at: iconDir, withIntermediateDirectories: true)
      return iconDir
    } catch {
      Log.error("AppCache", "Failed to create icon directory: \(error.localizedDescription)")
      return nil
    }
  }

  static func clearAllIconsOnDisk(iconDirectory: URL?) {
    guard let iconDir = iconDirectory else { return }
    let fm = FileManager.default
    if let files = try? fm.contentsOfDirectory(atPath: iconDir.path) {
      for file in files where file.hasSuffix(".png") || file.hasSuffix(".jpg") {
        try? fm.removeItem(at: iconDir.appendingPathComponent(file))
      }
    }
  }

  /// Returns `true` if the schema changed and the caller should treat icon cache as purged.
  static func ensureIconCacheSchema(iconDirectory: URL?) -> Bool {
    let current = UserDefaults.standard.integer(forKey: Keys.iconCacheSchema)
    guard current != Keys.iconCacheSchemaVersion else { return false }

    clearAllIconsOnDisk(iconDirectory: iconDirectory)
    PlatformImage.purgeAllCache()
    UserDefaults.standard.set(Keys.iconCacheSchemaVersion, forKey: Keys.iconCacheSchema)
    return true
  }

  // MARK: - Apps cache

  static func loadAppsCache() -> [String: [RokuApp]] {
    guard let data = UserDefaults.standard.data(forKey: Keys.apps),
          let cached = try? JSONDecoder().decode([String: [RokuApp]].self, from: data)
    else { return [:] }
    return cached
  }

  static func saveAppsCache(_ appsByDevice: [String: [RokuApp]]) {
    guard let data = try? JSONEncoder().encode(appsByDevice) else { return }
    UserDefaults.standard.set(data, forKey: Keys.apps)
  }

  static func loadAppsFetchedAt() -> [String: TimeInterval] {
    if let data = UserDefaults.standard.data(forKey: Keys.appsFetchedAt),
       let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
    {
      return decoded
    }
    return [:]
  }

  static func saveAppsFetchedAt(_ map: [String: TimeInterval]) {
    if let data = try? JSONEncoder().encode(map) {
      UserDefaults.standard.set(data, forKey: Keys.appsFetchedAt)
    }
  }

  // MARK: - MRU

  static func loadMRU() -> [String: [String: TimeInterval]] {
    guard let data = UserDefaults.standard.data(forKey: Keys.mru),
          let decoded = try? JSONDecoder().decode([String: [String: TimeInterval]].self, from: data)
    else { return [:] }
    return decoded
  }

  static func saveMRU(_ map: [String: [String: TimeInterval]]) {
    if let data = try? JSONEncoder().encode(map) {
      UserDefaults.standard.set(data, forKey: Keys.mru)
    }
  }

  // MARK: - Icon hashes

  static func loadHashes() -> [String: IconMeta] {
    guard let data = UserDefaults.standard.data(forKey: Keys.hashes) else { return [:] }
    return (try? JSONDecoder().decode([String: IconMeta].self, from: data)) ?? [:]
  }

  static func saveHashes(_ metas: [String: IconMeta]) {
    if let data = try? JSONEncoder().encode(metas) {
      UserDefaults.standard.set(data, forKey: Keys.hashes)
    }
  }
}
