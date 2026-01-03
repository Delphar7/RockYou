import Foundation

/// Best-effort fallback reader for the app's preferences plist.
///
/// Why this exists:
/// - `UserDefaults` can briefly serve stale values in some simulator install flows.
/// - Some legacy state historically lived in the preferences plist.
///
/// This is intentionally "read-only" and defensive.
enum PreferencesPlist {
  static func value(forKey key: String, bundle: Bundle = .main) -> Any? {
    guard let bundleId = bundle.bundleIdentifier,
          let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    else { return nil }

    let url = lib
      .appendingPathComponent("Preferences", isDirectory: true)
      .appendingPathComponent("\(bundleId).plist")

    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          let dict = plist as? [String: Any]
    else { return nil }

    return dict[key]
  }

  static func data(forKey key: String, bundle: Bundle = .main) -> Data? {
    if let data = value(forKey: key, bundle: bundle) as? Data { return data }
    if let nsData = value(forKey: key, bundle: bundle) as? NSData { return Data(referencing: nsData) }
    return nil
  }

  static func string(forKey key: String, bundle: Bundle = .main) -> String? {
    value(forKey: key, bundle: bundle) as? String
  }
}
