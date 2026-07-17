// RokuAuthKeyStore.swift
// RockYou
//
// Runtime source for the Roku ECP-2 authentication key.
//
// The key value is deliberately NOT compiled into the app and never checked into the repo.
// It lives in an app-scoped CloudKit record (public database, default zone) and is fetched
// once at runtime, then cached in the keychain so subsequent launches work offline. The
// record grants read to "_icloud" only, so fetching it requires both a build provisioned
// for this app's CloudKit container AND a signed-in iCloud account on the device.
//
// The key is a Roku vendor secret that leaked, not a per-user credential — anyone with the
// device can still recover it. Keychain storage (vs. a plaintext UserDefaults plist) just
// keeps it out of casual inspection and off-device backups.

import CloudKit
import Foundation
import Security

actor RokuAuthKeyStore {
  static let shared = RokuAuthKeyStore()

  enum KeyError: Error, LocalizedError {
    case notFound
    case missingValue

    var errorDescription: String? {
      switch self {
      case .notFound:
        return "ECP-2 auth key record not found in CloudKit"
      case .missingValue:
        return "ECP-2 auth key record exists but has no value"
      }
    }
  }

  // MARK: - Schema

  private enum Schema {
    static let recordType = "AppConfig"
    static let nameField = "name"
    static let valueField = "value"
    static let keyRecordName = "roku-ecp2-auth-key"
  }

  // Keychain generic-password identity for the cached key.
  private static let keychainService = "com.rockyou.ecp2"
  private static let keychainAccount = "authKey.v1"
  // Legacy plaintext location written by builds before the keychain migration; deleted on read.
  private static let legacyDefaultsKey = "com.rockyou.ecp2.authKey.v1"

  // MARK: - State

  private var cached: String?
  private var inflight: Task<String, Error>?

  // MARK: - Public

  /// Warm the cache in the background so the first authentication doesn't pay fetch latency.
  /// Failures are ignored here; `authKey()` surfaces them when the key is actually needed.
  nonisolated func prefetch() {
    Task { _ = try? await authKey() }
  }

  /// Return the ECP-2 auth key: memory cache → keychain → CloudKit public database.
  /// Concurrent callers coalesce onto a single CloudKit fetch.
  func authKey() async throws -> String {
    if let cached { return cached }

    if let stored = migrateOrReadKeychain(), !stored.isEmpty {
      cached = stored
      return stored
    }

    if let inflight { return try await inflight.value }

    let task = Task<String, Error> {
      // Query by a `name` field rather than fetching a fixed record ID: cktool-based
      // seeding cannot choose record names, and this keeps AppConfig usable for future
      // config entries.
      let container = CKContainer(identifier: CloudKitConfig.containerId)
      let query = CKQuery(
        recordType: Schema.recordType,
        predicate: NSPredicate(format: "%K == %@", Schema.nameField, Schema.keyRecordName))
      let (results, _) = try await container.publicCloudDatabase.records(
        matching: query, desiredKeys: [Schema.valueField], resultsLimit: 1)
      guard let record = try results.first?.1.get() else {
        throw KeyError.notFound
      }
      guard let key = record[Schema.valueField] as? String, !key.isEmpty else {
        throw KeyError.missingValue
      }
      return key
    }
    inflight = task
    defer { inflight = nil }

    do {
      let key = try await task.value
      cached = key
      writeKeychain(key)
      Log.info("RokuWS", "ECP-2 auth key loaded from CloudKit")
      return key
    } catch {
      Log.warn("RokuWS", "ECP-2 auth key fetch failed: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Keychain

  private func keychainQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.keychainService,
      kSecAttrAccount as String: Self.keychainAccount,
    ]
  }

  /// Read the cached key from the keychain, migrating a legacy UserDefaults value on first run
  /// (and scrubbing the plaintext copy).
  private func migrateOrReadKeychain() -> String? {
    if let migrated = UserDefaults.standard.string(forKey: Self.legacyDefaultsKey),
      !migrated.isEmpty
    {
      writeKeychain(migrated)
      UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
      return migrated
    }

    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else { return nil }
    return value
  }

  private func writeKeychain(_ value: String) {
    guard let data = value.data(using: .utf8) else { return }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]

    let status = SecItemUpdate(keychainQuery() as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insert = keychainQuery()
      insert.merge(attributes) { _, new in new }
      SecItemAdd(insert as CFDictionary, nil)
    }
  }
}
