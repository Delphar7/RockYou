//
//  PairingStore.swift
//  RockYou
//
//  Abstraction for TV ↔ Streaming Device pairings.
//  Currently uses UserDefaults, designed for easy CloudKit migration.
//

import Foundation
import Observation

// MARK: - Pairing Model
struct TVPairing: Codable, Identifiable, Equatable {
  var id: String { tvId }  // TV is the anchor
  let tvId: String
  let streamerId: String

  // Optional cached names for display (may be stale)
  var tvName: String?
  var streamerName: String?
}

// MARK: - Storage Protocol
/// Protocol for pairing storage - implement for different backends
@MainActor
protocol PairingStorageBackend: Sendable {
  func load() -> [TVPairing]
  func save(_ pairings: [TVPairing])
}

// MARK: - UserDefaults Backend (Local)
struct UserDefaultsPairingBackend: PairingStorageBackend {
  private let key = "com.rockyou.tvpairings"

  func load() -> [TVPairing] {
    let defaults = UserDefaults.standard

    let storedData: Data? = {
      if let data = defaults.data(forKey: key) { return data }
      if let data = preferencesPlistValue(forKey: key) as? Data { return data }
      if let nsData = preferencesPlistValue(forKey: key) as? NSData { return Data(referencing: nsData) }
      return nil
    }()

    if let data = storedData {
      if let pairings = try? JSONDecoder().decode([TVPairing].self, from: data) {
        return pairings
      }

      // Legacy format: { tvId: streamerId }
      if let dict = try? JSONDecoder().decode([String: String].self, from: data) {
        Log.info("PairingStore", "Migrated legacy tvpairings dictionary (Data)")
        return dict.map { TVPairing(tvId: $0.key, streamerId: $0.value) }
      }

      DebugBuild.run {
        let prefix = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
        Log.warn("PairingStore", "Failed to decode tvpairings Data (len=\(data.count)) prefix=\(prefix)")
      }
      return []
    }

    // Legacy storage: property-list dictionary
    if let dict = defaults.dictionary(forKey: key) as? [String: String], !dict.isEmpty {
      Log.info("PairingStore", "Migrated legacy tvpairings dictionary (plist)")
      return dict.map { TVPairing(tvId: $0.key, streamerId: $0.value) }
    }

    return []
  }

  private func preferencesPlistValue(forKey key: String) -> Any? {
    guard let bundleId = Bundle.main.bundleIdentifier,
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

  func save(_ pairings: [TVPairing]) {
    guard let data = try? JSONEncoder().encode(pairings) else { return }
    UserDefaults.standard.set(data, forKey: key)
    DebugBuild.run { UserDefaults.standard.synchronize() }
  }
}

// MARK: - Observable Pairing Store
/// Main store that the UI observes. Wraps a backend for persistence.
@Observable
@MainActor
final class PairingStore {
  private(set) var pairings: [TVPairing] = []
  private(set) var currentTVId: String?
  private(set) var currentSelection: DeviceSelection?
  private let backend: PairingStorageBackend

  // CloudKit sharing state
  private(set) var isShared: Bool = false
  private(set) var shareParticipants: [String] = []
  private(set) var isSyncing: Bool = false
  private(set) var cloudKitBlockedMessage: String?

  // CloudKit backend reference (for sharing operations)
  private var cloudBackend: CloudKitHouseholdPairingBackend? {
    backend as? CloudKitHouseholdPairingBackend
  }

  private let currentTVKey = "com.rockyou.currenttvid"
  private let currentSelectionKey = "com.rockyou.currentSelection"

  convenience init() {
    self.init(backend: CloudKitHouseholdPairingBackend())
  }

  init(backend: PairingStorageBackend) {
    DebugBuild.run {
      // When installing via `simctl install`, cfprefsd can briefly serve stale values.
      CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }

    self.backend = backend
    self.pairings = backend.load()
    self.currentSelection = loadCurrentSelection()
    self.currentTVId = {
      if let currentSelection {
        switch currentSelection {
        case .tv(let id): return id
        case .streamer: return nil
        }
      }
      return UserDefaults.standard.string(forKey: currentTVKey)
        ?? (preferencesPlistValue(forKey: currentTVKey) as? String)
    }()
    migrateCurrentTVSelectionIfNeeded()
    migrateCurrentSelectionIfNeeded()

    Log.debug(
      "PairingStore",
      "Loaded pairings=\(pairings.count), currentSelection=\(currentSelection?.id ?? "nil"), currentTVId=\(currentTVId ?? "nil"), hasCurrentTVKey=\(UserDefaults.standard.object(forKey: currentTVKey) != nil)"
    )

    // Set up CloudKit callbacks
    if let cloud = backend as? CloudKitHouseholdPairingBackend {
      cloud.onCloudUpdate = { [weak self] pairings in
        self?.pairings = pairings
      }
      cloud.onShareStatusChanged = { [weak self] isShared, participants in
        self?.isShared = isShared
        self?.shareParticipants = participants
      }
      cloud.onCloudAccessStateChanged = { [weak self] state in
        guard let self else { return }
        switch state {
        case .unknown, .ready:
          self.cloudKitBlockedMessage = nil
        case .blocked(_, let message):
          self.cloudKitBlockedMessage = message
        }
      }
    }
  }

  // MARK: - Current TV Selection

  /// The currently selected TV pairing (if any)
  var currentPairing: TVPairing? {
    guard let tvId = currentTVId else { return nil }
    return pairingForTV(tvId)
  }

  /// Set the current TV and fetch its properties
  func selectTV(_ tvId: String?) {
    currentTVId = tvId
    currentSelection = tvId.map { .tv(id: $0) }
    if let tvId = tvId {
      UserDefaults.standard.set(tvId, forKey: currentTVKey)
      persistCurrentSelection()
      flushDefaultsIfDebug()
      // Fetch properties async
      Task {
        await fetchPropertiesForSelectedTV(tvId)
      }
    } else {
      UserDefaults.standard.removeObject(forKey: currentTVKey)
      clearCurrentSelection()
      flushDefaultsIfDebug()
    }
  }

  /// Set the current selection (TV or Streamer).
  ///
  /// Today most of the app is still TV-oriented, so selecting a streamer clears `currentTVId`.
  func select(_ selection: DeviceSelection?) {
    currentSelection = selection
    switch selection {
    case .none:
      currentTVId = nil
      UserDefaults.standard.removeObject(forKey: currentTVKey)
      clearCurrentSelection()
    case .tv(let id):
      currentTVId = id
      UserDefaults.standard.set(id, forKey: currentTVKey)
      persistCurrentSelection()
      flushDefaultsIfDebug()
      Task { await fetchPropertiesForSelectedTV(id) }
    case .streamer:
      currentTVId = nil
      UserDefaults.standard.removeObject(forKey: currentTVKey)
      persistCurrentSelection()
      flushDefaultsIfDebug()
    }
  }

  private func loadCurrentSelection() -> DeviceSelection? {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: currentSelectionKey) {
      return try? JSONDecoder().decode(DeviceSelection.self, from: data)
    }
    if let data = preferencesPlistValue(forKey: currentSelectionKey) as? Data {
      return try? JSONDecoder().decode(DeviceSelection.self, from: data)
    }
    if let nsData = preferencesPlistValue(forKey: currentSelectionKey) as? NSData {
      return try? JSONDecoder().decode(DeviceSelection.self, from: Data(referencing: nsData))
    }
    return nil
  }

  private func persistCurrentSelection() {
    guard let currentSelection else { return }
    guard let data = try? JSONEncoder().encode(currentSelection) else { return }
    UserDefaults.standard.set(data, forKey: currentSelectionKey)
  }

  private func clearCurrentSelection() {
    UserDefaults.standard.removeObject(forKey: currentSelectionKey)
  }

  private func migrateCurrentSelectionIfNeeded() {
    // If we only have a legacy TV selection, seed the typed selection.
    if currentSelection == nil, let tvId = currentTVId {
      currentSelection = .tv(id: tvId)
      persistCurrentSelection()
    }
  }

  /// Fetch and log properties for the selected TV (and its paired streamer if any)
  @MainActor
  private func fetchPropertiesForSelectedTV(_ tvId: String) async {
    let discovery = RokuDiscoveryService.shared
    let ecpClient = RokuECPClient.shared

    // Find the TV in discovered devices
    guard let tv = discovery.tvs.first(where: { $0.id == tvId }) else {
      Log.warn("PairingStore", "Selected TV not found in discovered devices: \(tvId)")
      return
    }

    // Get the paired streamer (if any) while we're on MainActor
    let streamerId = streamerIdForTV(tvId)
    let streamer = streamerId.flatMap { sid in
      discovery.streamingDevices.first { $0.id == sid }
    }

    Log.info("PairingStore", "══════════════════════════════════════════════")
    Log.info("PairingStore", "TV Selected: \(tv.name)")
    Log.info("PairingStore", "══════════════════════════════════════════════")

    // Fetch TV properties (debug helper).
    // NOTE: This is intentionally compiled out unless HTTP fallback is explicitly enabled.
    #if ROCKYOU_ENABLE_ECP1_FALLBACK
      if let tvProps = await ecpClient.fetchProperties(for: tv) {
        // Log each line separately for readability in Console
        for line in tvProps.summary.components(separatedBy: "\n") {
          Log.debug("RokuECP-TV", line)
        }
      }
    #else
      Log.debug("PairingStore", "(properties dump disabled; build with -DROCKYOU_ENABLE_ECP1_FALLBACK to enable)")
    #endif

    // If paired, also fetch streamer properties
    if let streamer = streamer {
      Log.info("PairingStore", "Paired Streamer: \(streamer.name)")
      #if ROCKYOU_ENABLE_ECP1_FALLBACK
        if let streamerProps = await ecpClient.fetchProperties(for: streamer) {
          for line in streamerProps.summary.components(separatedBy: "\n") {
            Log.debug("RokuECP-Streamer", line)
          }
        }
      #endif
    } else {
      Log.info("PairingStore", "No paired streamer (using TV's built-in Roku)")
    }
  }

  /// Check if we have any configured pairings
  var hasPairings: Bool { !pairings.isEmpty }

  // MARK: - Query

  /// Get the streamer ID paired with a TV
  func streamerIdForTV(_ tvId: String) -> String? {
    pairings.first { $0.tvId == tvId }?.streamerId
  }

  /// Get the TV ID that a streamer is paired with
  func tvIdForStreamer(_ streamerId: String) -> String? {
    pairings.first { $0.streamerId == streamerId }?.tvId
  }

  /// Get full pairing for a TV
  func pairingForTV(_ tvId: String) -> TVPairing? {
    pairings.first { $0.tvId == tvId }
  }

  /// Dictionary access (TV ID → Streamer ID) for compatibility
  var asDictionary: [String: String] {
    Dictionary(uniqueKeysWithValues: pairings.map { ($0.tvId, $0.streamerId) })
  }

  // MARK: - Mutate

  /// Pair a TV with a streaming device (removes any existing pairing for either)
  func pair(tvId: String, streamerId: String, tvName: String? = nil, streamerName: String? = nil) {
    // Remove any existing pairings involving either device
    pairings.removeAll { $0.tvId == tvId || $0.streamerId == streamerId }

    // Add new pairing
    let pairing = TVPairing(
      tvId: tvId,
      streamerId: streamerId,
      tvName: tvName,
      streamerName: streamerName
    )
    pairings.append(pairing)
    save()
  }

  /// Unpair a TV (remove its pairing)
  func unpairTV(_ tvId: String) {
    pairings.removeAll { $0.tvId == tvId }
    save()
  }

  /// Swap pairings between two TVs
  func swap(tv1: String, tv2: String) {
    guard let pairing1 = pairingForTV(tv1),
          let pairing2 = pairingForTV(tv2)
    else { return }

    // Remove both
    pairings.removeAll { $0.tvId == tv1 || $0.tvId == tv2 }

    // Re-add swapped
    pairings.append(TVPairing(
      tvId: tv1,
      streamerId: pairing2.streamerId,
      tvName: pairing1.tvName,
      streamerName: pairing2.streamerName
    ))
    pairings.append(TVPairing(
      tvId: tv2,
      streamerId: pairing1.streamerId,
      tvName: pairing2.tvName,
      streamerName: pairing1.streamerName
    ))
    save()
  }

  // MARK: - Persistence

  private func save() {
    backend.save(pairings)
  }

  // MARK: - Persistence Helpers

  private func migrateCurrentTVSelectionIfNeeded() {
    guard currentTVId == nil else { return }

    let defaults = UserDefaults.standard
    let legacyKeys = [
      "selectedTVId",
      "selectedTvId",
      "currentTVId",
      "currentTvId",
      "selectedDeviceId",
    ]

    for key in legacyKeys {
      guard let raw = defaults.string(forKey: key), !raw.isEmpty else { continue }

      // If the legacy value is a streamer id, map to its TV id when possible.
      let tvId = pairings.first(where: { $0.tvId == raw })?.tvId
        ?? tvIdForStreamer(raw)
        ?? raw

      currentTVId = tvId
      defaults.set(tvId, forKey: currentTVKey)
      flushDefaultsIfDebug()
      Log.info("PairingStore", "Migrated current TV selection from '\(key)'")
      return
    }

    // If we have exactly one pairing, pick it (better than starting empty).
    if pairings.count == 1, let only = pairings.first {
      currentTVId = only.tvId
      defaults.set(only.tvId, forKey: currentTVKey)
      flushDefaultsIfDebug()
      Log.info("PairingStore", "Initialized current TV selection from single pairing")
    }
  }

  private func flushDefaultsIfDebug() {
    DebugBuild.run { UserDefaults.standard.synchronize() }
  }

  private func preferencesPlistValue(forKey key: String) -> Any? {
    guard let bundleId = Bundle.main.bundleIdentifier,
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

  // MARK: - CloudKit Sharing

  /// Create a share link for household members. Returns the share URL.
  func createShareURL() async throws -> URL {
    guard let cloud = cloudBackend else {
      throw NSError(domain: "PairingStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "CloudKit not available"])
    }
    isSyncing = true
    defer { isSyncing = false }
    let share = try await cloud.createShare()
    guard let url = share.url else {
      throw NSError(domain: "PairingStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "No share URL returned"])
    }
    return url
  }

  /// Accept a share from another user
  func acceptShare(metadata: CKShare.Metadata) async throws {
    guard let cloud = cloudBackend else { return }
    isSyncing = true
    defer { isSyncing = false }
    try await cloud.acceptShare(metadata: metadata)
  }

  /// Refresh from CloudKit
  func refreshFromCloud() async {
    guard let cloud = cloudBackend else { return }
    isSyncing = true
    await cloud.fetchFromCloud()
    isSyncing = false
  }
}

// MARK: - Singleton
extension PairingStore {
  @MainActor
  static let shared = PairingStore()
}

// MARK: - CloudKit Backend

import CloudKit

/// Pairing persistence backed by UserDefaults + CloudKit (household zone/share).
final class CloudKitHouseholdPairingBackend: PairingStorageBackend {
  private let localBackend = UserDefaultsPairingBackend()
  private let store = CloudKitHouseholdStore.shared

  // Callbacks for async updates
  var onCloudUpdate: (([TVPairing]) ->  Void)?
  var onShareStatusChanged: ((Bool, [String]) -> Void)?
  var onCloudAccessStateChanged: ((CloudKitHouseholdStore.CloudAccessState) -> Void)?

  init() {
    store.startIfNeeded()

    store.onCloudAccessStateChanged = { [weak self] state in
      self?.onCloudAccessStateChanged?(state)
    }
    onCloudAccessStateChanged?(store.cloudAccessState)

    store.onPairingsUpdated = { [weak self] pairings in
      guard let self else { return }
      self.localBackend.save(pairings)
      self.onCloudUpdate?(pairings)
    }

    store.onShareStatusChanged = { [weak self] isShared, participants in
      self?.onShareStatusChanged?(isShared, participants)
    }
  }

  func load() -> [TVPairing] {
    localBackend.load()
  }

  func save(_ pairings: [TVPairing]) {
    localBackend.save(pairings)
    Task { @MainActor in
      await store.applyPairings(pairings)
    }
  }

  func fetchFromCloud() async {
    await store.refreshFromCloud(force: true)
  }

  func createShare() async throws -> CKShare {
    try await store.createShare()
  }

  func acceptShare(metadata: CKShare.Metadata) async throws {
    try await store.acceptShare(metadata: metadata)
  }
}
