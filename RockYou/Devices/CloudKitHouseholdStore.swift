//
//  CloudKitHouseholdStore.swift
//  RockYou
//
//  Shared household dataset in CloudKit:
//  - Structured TV pairings (TVPairing records)
//  - Per-device app MRU (DeviceAppMRU records)
//  - Single share rooted at RockYouRoot in RockYouZone
//

import CloudKit
import Foundation

@MainActor
final class CloudKitHouseholdStore {
  static let shared = CloudKitHouseholdStore()

  // MARK: - Schema

  private enum Schema {
    static let containerId = "iCloud.com.jtr.RockYou"

    static let zoneName = "RockYouZone"
    static let rootRecordType = "RockYouRoot"
    static let rootRecordName = "root"
    static let expectedSchemaVersion: Int = 1

    static let pairingRecordType = "TVPairing"
    static let mruRecordType = "DeviceAppMRU"

    static let legacyZoneName = "PairingsZone"
    static let legacySubscriptionId = "pairings-sub"

    static let privateSubscriptionId = "rockyou-private-db-sub"
    static let sharedSubscriptionId = "rockyou-shared-db-sub"

    // Per-user (non-shared) config record in the *private* DB default zone.
    static let userConfigRecordType = "RockYouUserConfig"
    static let userConfigRecordName = "userConfig"
    static let userConfigActiveSharedZoneNameField = "activeSharedZoneName"
    static let userConfigActiveSharedZoneOwnerNameField = "activeSharedZoneOwnerName"
    static let userConfigUpdatedAtField = "updatedAt"
  }

  // MARK: - Persistence keys

  private enum DefaultsKey {
    static let cachedMRU = "com.rockyou.cloudkit.mru.cache.v1"
    static let cachedPairings = "com.rockyou.cloudkit.pairings.cache.v1"
    static let zoneTokenPrivate = "com.rockyou.cloudkit.zoneToken.private.v1"
    static let zoneTokenShared = "com.rockyou.cloudkit.zoneToken.shared.v1"

    // "Active household" hint (local mirror of private, per-user config record)
    static let activeHouseholdSharedZoneName =
      "com.rockyou.cloudkit.activeHousehold.sharedZoneName.v1"
    static let activeHouseholdSharedZoneOwnerName =
      "com.rockyou.cloudkit.activeHousehold.sharedZoneOwnerName.v1"
  }

  // MARK: - Cloud access state

  enum CloudAccessState: Equatable, Sendable {
    case unknown
    case ready(schemaVersion: Int)
    case blocked(foundSchemaVersion: Int?, message: String)
  }

  private(set) var cloudAccessState: CloudAccessState = .unknown {
    didSet {
      if oldValue != cloudAccessState {
        onCloudAccessStateChanged?(cloudAccessState)
      }
    }
  }

  var isCloudAccessReady: Bool {
    if case .ready = cloudAccessState { return true }
    return false
  }

  var isCloudAccessBlocked: Bool {
    if case .blocked = cloudAccessState { return true }
    return false
  }

  // MARK: - State

  private let container = CKContainer(identifier: Schema.containerId)
  private var started = false

  /// Last observed schema version in the shared household zone (if accessible).
  /// This is informational only for now; we don't attempt to upgrade shared zones.
  private(set) var lastObservedSharedSchemaVersion: Int?

  // Account status caching (avoid repeated checks / log spam)
  private var cachedAccountStatus: CKAccountStatus?
  private var lastAccountStatusCheckedAt: Date = .distantPast
  private let accountStatusCacheTTL: TimeInterval = 60

  // Refresh coalescing (CloudKit calls are easy to spam accidentally)
  private var isRefreshingFromCloud: Bool = false
  private var lastRefreshFromCloudAt: Date = .distantPast
  private let refreshMinInterval: TimeInterval = 30

  private var refreshDebounceTask: Task<Void, Never>?

  // Shared zone lookup caching (avoid repeated `allRecordZones()` calls)
  private enum SharedZoneCache {
    case unknown
    case none(checkedAt: Date)
    case some(zoneID: CKRecordZone.ID, checkedAt: Date)
  }
  private var sharedZoneCache: SharedZoneCache = .unknown
  private let sharedZoneCacheTTL: TimeInterval = 5 * 60

  private var cachedPairings: [TVPairing] = []
  private var cachedMRUByDevice: [String: [String: Date]] = [:]

  // For MRU write-side filtering
  private var lastSeenActiveAppByDevice: [String: String] = [:]
  private var pendingMRURetryTaskByDevice: [String: Task<Void, Never>] = [:]
  private var pendingMRUWriteTaskByDevice: [String: Task<Void, Never>] = [:]
  private var lastMRUWriteAtByDevice: [String: Date] = [:]

  // Watch bridging: remember the last device the watch asked about so we can push reorder updates.
  var lastAppsDeviceIdRequestedByWatch: String?

  // MARK: - Callbacks

  var onPairingsUpdated: (([TVPairing]) -> Void)?
  var onShareStatusChanged: ((Bool, [String]) -> Void)?
  var onMRUUpdated: ((String, [String: Date]) -> Void)?
  var onCloudAccessStateChanged: ((CloudAccessState) -> Void)?

  private init() {
    loadCaches()
  }

  // MARK: - Public

  func startIfNeeded() {
    guard !started else { return }
    started = true

    // Observe device state changes so we can record MRU.
    DeviceStateManager.shared.addStateChangedHandler { [weak self] deviceId, state in
      self?.handleDeviceStateChanged(deviceId: deviceId, state: state)
    }

    Task {
      // Hydrate "active household" hint from the private DB so other devices
      // don't need to enumerate shared zones (no polling).
      await hydrateActiveHouseholdHintFromPrivateConfig()

      let ok = await ensureCloudSchemaReady()
      guard ok else { return }

      await ensureSubscriptions()
      await refreshFromCloud(force: true)
    }
  }

  func refreshFromCloud(force: Bool = false) async {
    guard isCloudAccessReady else { return }
    let now = Date()
    if !force, now.timeIntervalSince(lastRefreshFromCloudAt) < refreshMinInterval {
      return
    }
    if isRefreshingFromCloud { return }
    isRefreshingFromCloud = true
    defer {
      isRefreshingFromCloud = false
      lastRefreshFromCloudAt = Date()
    }

    // Pull from shared first if present, else private.
    do {
      if let (db, zoneID) = try await resolveSharedZoneIfPresent() {
        await fetchZoneChanges(
          database: db, zoneID: zoneID, defaultsTokenKey: DefaultsKey.zoneTokenShared)
        return
      }
    } catch {
      Log.warn("CloudKit", "Shared zone lookup failed: \(error.localizedDescription)")
    }

    do {
      let zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
      await fetchZoneChanges(
        database: container.privateCloudDatabase, zoneID: zoneID,
        defaultsTokenKey: DefaultsKey.zoneTokenPrivate)
    }
  }

  func createShare() async throws -> CKShare {
    guard isCloudAccessReady else {
      if case .blocked(_, let message) = cloudAccessState {
        throw NSError(
          domain: "CloudKit", code: 1001, userInfo: [NSLocalizedDescriptionKey: message])
      }
      throw NSError(
        domain: "CloudKit", code: 1001,
        userInfo: [
          NSLocalizedDescriptionKey: "iCloud sync is not ready yet. Please try again shortly."
        ])
    }
    let zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
    let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: zoneID)

    let rootRecord: CKRecord
    do {
      rootRecord = try await container.privateCloudDatabase.record(for: rootID)
    } catch let error as CKError where error.code == .unknownItem {
      let newRoot = CKRecord(recordType: Schema.rootRecordType, recordID: rootID)
      newRoot["schemaVersion"] = 1 as CKRecordValue
      newRoot["updatedAt"] = Date() as CKRecordValue
      rootRecord = try await container.privateCloudDatabase.save(newRoot)
    }

    // If a share already exists for the root record, reuse it.
    // (This is especially important in production where a household may already be shared.)
    if let existingRef = rootRecord.share {
      let existing = try await container.privateCloudDatabase.record(for: existingRef.recordID)
      if let existingShare = existing as? CKShare {
        return existingShare
      }
    }

    let share = CKShare(rootRecord: rootRecord)
    share[CKShare.SystemFieldKey.title] = "RockYou Household" as CKRecordValue
    share.publicPermission = .none

    let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
    op.isAtomic = true

    // Capture the server-returned share (this is the one most likely to have `url` populated,
    // and CloudKit may reuse an existing share rather than persisting the newly-created recordID).
    let lock = NSLock()
    var serverShare: CKShare?

    op.perRecordSaveBlock = { _, result in
      if case .success(let record) = result, let saved = record as? CKShare {
        lock.lock()
        serverShare = saved
        lock.unlock()
      }
    }

    let savedShare: CKShare? = try await withCheckedThrowingContinuation { cont in
      op.modifyRecordsResultBlock = { result in
        switch result {
        case .success:
          lock.lock()
          let s = serverShare
          lock.unlock()
          cont.resume(returning: s)
        case .failure(let error):
          cont.resume(throwing: error)
        }
      }
      self.container.privateCloudDatabase.add(op)
    }

    if let savedShare { return savedShare }

    // Fallback: refetch root to see if CloudKit associated an existing share.
    do {
      let refreshedRoot = try await container.privateCloudDatabase.record(for: rootID)
      if let existingRef = refreshedRoot.share {
        let existing = try await container.privateCloudDatabase.record(for: existingRef.recordID)
        if let existingShare = existing as? CKShare { return existingShare }
      }
    } catch {
      Log.warn(
        "CloudKit", "Failed to refetch root/share after share save: \(error.localizedDescription)")
    }

    // Last resort: return the in-memory share.
    return share
  }

  func acceptShare(metadata: CKShare.Metadata) async throws {
    guard isCloudAccessReady else {
      if case .blocked(_, let message) = cloudAccessState {
        throw NSError(
          domain: "CloudKit", code: 1002, userInfo: [NSLocalizedDescriptionKey: message])
      }
      throw NSError(
        domain: "CloudKit", code: 1002,
        userInfo: [
          NSLocalizedDescriptionKey: "iCloud sync is not ready yet. Please try again shortly."
        ])
    }
    try await container.accept(metadata)
    invalidateSharedZoneCache()
    await persistActiveHouseholdHintFromAcceptedShare(metadata: metadata)
    await refreshFromCloud(force: true)
  }

  func applyPairings(_ pairings: [TVPairing]) async {
    guard isCloudAccessReady else { return }
    let (database, zoneID, rootID): (CKDatabase, CKRecordZone.ID, CKRecord.ID)
    do {
      (database, zoneID, rootID) = try await resolveActiveHouseholdWriteTarget()
    } catch {
      Log.warn(
        "CloudKit", "Failed to resolve zone for pairings write: \(error.localizedDescription)")
      return
    }

    // Diff vs cache.
    let old = Dictionary(uniqueKeysWithValues: cachedPairings.map { ($0.tvId, $0) })
    let new = Dictionary(uniqueKeysWithValues: pairings.map { ($0.tvId, $0) })

    var recordsToSave: [CKRecord] = []
    var recordIDsToDelete: [CKRecord.ID] = []

    for (tvId, pairing) in new {
      if old[tvId] == pairing { continue }
      let recID = CKRecord.ID(
        recordName: "pairing|\(sanitizeRecordComponent(tvId))", zoneID: zoneID)
      let record = CKRecord(recordType: Schema.pairingRecordType, recordID: recID)
      record["tvId"] = pairing.tvId as CKRecordValue
      record["streamerId"] = pairing.streamerId as CKRecordValue
      if let tvName = pairing.tvName { record["tvName"] = tvName as CKRecordValue }
      if let streamerName = pairing.streamerName {
        record["streamerName"] = streamerName as CKRecordValue
      }
      record.parent = CKRecord.Reference(recordID: rootID, action: .none)
      recordsToSave.append(record)
    }

    for (tvId, _) in old {
      if new[tvId] != nil { continue }
      let recID = CKRecord.ID(
        recordName: "pairing|\(sanitizeRecordComponent(tvId))", zoneID: zoneID)
      recordIDsToDelete.append(recID)
    }

    guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else { return }

    do {
      let op = CKModifyRecordsOperation(
        recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
      op.isAtomic = false
      _ = try await withCheckedThrowingContinuation { cont in
        op.modifyRecordsResultBlock = { result in
          switch result {
          case .success(let r):
            cont.resume(returning: r)
          case .failure(let error):
            cont.resume(throwing: error)
          }
        }
        database.add(op)
      }
    } catch {
      Log.warn("CloudKit", "Failed to write pairings: \(error.localizedDescription)")
      return
    }

    // Update local cache immediately (UI responsiveness) and let zone changes reconcile later.
    cachedPairings = pairings
    savePairingsCache()
    onPairingsUpdated?(pairings)
  }

  func upsertMRU(deviceId: String, appId: String, lastUsedAt: Date, source: String) async {
    guard isCloudAccessReady else { return }

    do {
      let (database, zoneID, rootID) = try await resolveActiveHouseholdWriteTarget()

      let recID = CKRecord.ID(
        recordName: "mru|\(sanitizeRecordComponent(deviceId))|\(sanitizeRecordComponent(appId))",
        zoneID: zoneID
      )

      let record = CKRecord(recordType: Schema.mruRecordType, recordID: recID)
      record["deviceId"] = deviceId as CKRecordValue
      record["appId"] = appId as CKRecordValue
      record["lastUsedAt"] = lastUsedAt as CKRecordValue
      record["source"] = source as CKRecordValue
      record["writerClientId"] = Self.writerClientId as CKRecordValue
      record.parent = CKRecord.Reference(recordID: rootID, action: .none)

      do {
        try await database.save(record)
      } catch let error as CKError {
        // Handle conflict errors (two devices writing simultaneously)
        if error.code == .serverRecordChanged {
          Log.debug(
            "CloudKit",
            "MRU write conflict for deviceId=\(deviceId) appId=\(appId); will sync on next refresh"
          )
          // Conflict is fine - CloudKit sync will bring in the latest value
        } else {
          Log.warn(
            "CloudKit",
            "Failed to upsert MRU deviceId=\(deviceId) appId=\(appId): \(error.localizedDescription)"
          )
        }
        // Note: Local cache already updated, so UI is responsive. CloudKit sync will reconcile.
      } catch {
        Log.warn(
          "CloudKit",
          "Failed to upsert MRU deviceId=\(deviceId) appId=\(appId): \(error.localizedDescription)")
        // Note: Local cache already updated, so UI is responsive. CloudKit sync will reconcile.
      }
    } catch {
      Log.warn("CloudKit", "Failed to resolve zone for MRU write: \(error.localizedDescription)")
      return
    }
  }

  // MARK: - Helpers

  private static let writerClientId: String = {
    let key = "com.rockyou.cloudkit.writerClientId.v1"
    if let existing = UserDefaults.standard.string(forKey: key) { return existing }
    let new = UUID().uuidString
    UserDefaults.standard.set(new, forKey: key)
    return new
  }()

  private func sanitizeRecordComponent(_ input: String) -> String {
    // CloudKit record names must be URL-safe-ish; keep this simple and deterministic.
    let allowed = Set(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".map { $0 })
    return String(input.map { allowed.contains($0) ? $0 : "_" })
  }

  private func handleDeviceStateChanged(deviceId: String, state: DeviceState) {
    guard let appId = state.activeApp, !appId.isEmpty else { return }

    let old = lastSeenActiveAppByDevice[deviceId]
    guard old != appId else { return }

    // Only record MRU for apps that exist in the installed list we currently have.
    // IMPORTANT: Don't mark as "seen" until we successfully record MRU; otherwise if the app list
    // isn't loaded yet, we lose the chance to record when it arrives (common with Netflix).
    let installed = AppCacheManager.shared.apps(for: deviceId)
    guard installed.contains(where: { $0.id == appId }) else {
      Log.debug(
        "CloudKit",
        "Deferring MRU write for unknown appId=\(appId) deviceId=\(deviceId) (not in installed list yet)"
      )
      scheduleMRURetry(deviceId: deviceId, appId: appId)
      return
    }

    recordMRU(deviceId: deviceId, appId: appId, source: "active-app")
  }

  private func scheduleMRURetry(deviceId: String, appId: String) {
    pendingMRURetryTaskByDevice[deviceId]?.cancel()
    pendingMRURetryTaskByDevice[deviceId] = Task { [weak self] in
      guard let self else { return }
      // Short delay to allow app list to load from cache/network.
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1.0s
      guard !Task.isCancelled else { return }

      // Ensure the active app is still the same.
      let current = DeviceStateManager.shared.state(for: deviceId).activeApp
      guard current == appId else { return }

      let installed = AppCacheManager.shared.apps(for: deviceId)
      guard installed.contains(where: { $0.id == appId }) else { return }

      self.recordMRU(deviceId: deviceId, appId: appId, source: "active-app-retry")
    }
  }

  private func recordMRU(deviceId: String, appId: String, source: String) {
    lastSeenActiveAppByDevice[deviceId] = appId

    // Capture timestamp once to use consistently for local cache and CloudKit write
    let timestamp = Date()

    // Update local MRU immediately for UI responsiveness.
    var map = cachedMRUByDevice[deviceId] ?? [:]
    map[appId] = timestamp
    cachedMRUByDevice[deviceId] = map
    saveMRUCache()
    AppCacheManager.shared.setMRU(map, for: deviceId)
    onMRUUpdated?(deviceId, map)

    // Debounce + throttle CloudKit writes.
    pendingMRUWriteTaskByDevice[deviceId]?.cancel()
    pendingMRUWriteTaskByDevice[deviceId] = Task { [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s debounce
      guard !Task.isCancelled else { return }

      // Ensure app is still current.
      let current = DeviceStateManager.shared.state(for: deviceId).activeApp
      guard current == appId else { return }

      // Throttle per device.
      let now = Date()
      let minInterval: TimeInterval = 15
      if let last = self.lastMRUWriteAtByDevice[deviceId] {
        let elapsed = now.timeIntervalSince(last)
        if elapsed < minInterval {
          let delay = minInterval - elapsed
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
      }

      guard !Task.isCancelled else { return }
      self.lastMRUWriteAtByDevice[deviceId] = now
      // Use the same timestamp we used for local cache to maintain consistency
      await self.upsertMRU(
        deviceId: deviceId, appId: appId, lastUsedAt: timestamp, source: source)
    }
  }

  /// Resolve the active household write target.
  /// - If a shared household zone is active/present, writes go to that shared DB/zone.
  /// - Otherwise, writes go to the private DB/zone (owner-only).
  private func resolveActiveHouseholdWriteTarget() async throws
    -> (database: CKDatabase, zoneID: CKRecordZone.ID, rootID: CKRecord.ID)
  {
    if let (sharedDB, sharedZoneID) = try await resolveSharedZoneIfPresent() {
      let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: sharedZoneID)
      return (sharedDB, sharedZoneID, rootID)
    }

    let zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
    let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: zoneID)
    return (container.privateCloudDatabase, zoneID, rootID)
  }

  // MARK: - Legacy reset / bootstrap

  private func ensureCloudSchemaReady() async -> Bool {
    // If we're already blocked due to schema mismatch, don't spam CloudKit.
    if case .blocked = cloudAccessState { return false }

    // If iCloud isn't available for this account/device, don't attempt schema probes/resets.
    let accountOK = await ensureCloudAccountAvailable()
    guard accountOK else { return false }

    // Read schema versions from both shared + private (best effort).
    let versions = await readSchemaVersions()
    lastObservedSharedSchemaVersion = versions.sharedSchemaVersion

    // Log schema read results (success + mismatch) to make diagnosis easy.
    if let sharedV = versions.sharedSchemaVersion {
      if sharedV == Schema.expectedSchemaVersion {
        Log.info(
          "CloudKit",
          "Read schemaVersion (shared RockYouRoot): expected v\(Schema.expectedSchemaVersion), found v\(sharedV)"
        )
      } else {
        if PlatformSecurityPolicy.isSimulator {
          // Simulator can be noisy; keep this informational.
          Log.info(
            "CloudKit",
            "Read schemaVersion (shared RockYouRoot) mismatch (simulator): expected v\(Schema.expectedSchemaVersion), found v\(sharedV)"
          )
        } else {
          Log.warn(
            "CloudKit",
            "Read schemaVersion (shared RockYouRoot) mismatch: expected v\(Schema.expectedSchemaVersion), found v\(sharedV)"
          )
        }
      }
    }

    if let privateV = versions.privateSchemaVersion {
      if privateV == Schema.expectedSchemaVersion {
        Log.info(
          "CloudKit",
          "Read schemaVersion (private RockYouRoot): expected v\(Schema.expectedSchemaVersion), found v\(privateV)"
        )
      } else {
        Log.warn(
          "CloudKit",
          "Read schemaVersion (private RockYouRoot) mismatch: expected v\(Schema.expectedSchemaVersion), found v\(privateV)"
        )
      }
    }

    // We only attempt to bootstrap/migrate the *private* database.
    // Shared household zones may be owned by another user; upgrading them is a separate decision.
    guard let privateSchemaVersion = versions.privateSchemaVersion else {
      // Missing → need to provision private schema
      Log.info(
        "CloudKit", "No schemaVersion found in RockYouRoot (private); bootstrapping iCloud schema")

      if DebugBuild.isEnabled {
        Log.info("CloudKit", "🧹 DEBUG: destructive reset of legacy/new zones before bootstrap")
        await destructiveResetLegacyAndNewZones()
      }

      // Attempt provisioning on all platforms. On Simulator this may fail due to missing
      // end-to-end encrypted key material (PCS/Manatee / user key sync), but we prefer to try
      // rather than pre-blocking, so simulators that *do* have iCloud configured can still work.
      do {
        try await ensureZoneAndRootExistInPrivateDB()
        cloudAccessState = .ready(schemaVersion: Schema.expectedSchemaVersion)
        return true
      } catch {
        if isLikelyCloudSchemaNotDeployed(error) {
          let message =
            "iCloud sync is unavailable because the CloudKit schema is not deployed to production yet. "
            + "Deploy the schema in the CloudKit Dashboard (Development → Production), then try again."
          Log.warn("CloudKit", "Bootstrap blocked: \(message) (\(error.localizedDescription))")
          cloudAccessState = .blocked(foundSchemaVersion: nil, message: message)
          return false
        }
        if isLikelyCloudAccountUnavailable(error) {
          let message = cloudAccountUnavailableMessage(for: error)
          if PlatformSecurityPolicy.isSimulator {
            Log.debug("CloudKit", "Bootstrap blocked (simulator): \(message)")
          } else {
            Log.error("CloudKit", "Bootstrap blocked: \(message)")
          }
          cloudAccessState = .blocked(foundSchemaVersion: nil, message: message)
          return false
        }
        // Transient error → retry later
        Log.warn("CloudKit", "Bootstrap failed (will retry later): \(error.localizedDescription)")
        cloudAccessState = .unknown
        scheduleSchemaProbeRetry()
        return false
      }
    }

    // Private schema version found → validate
    if privateSchemaVersion == Schema.expectedSchemaVersion {
      cloudAccessState = .ready(schemaVersion: privateSchemaVersion)
      return true
    }

    if privateSchemaVersion > Schema.expectedSchemaVersion {
      // Higher schema version: newer app created this. Block to prevent data corruption.
      // We assume we can read newer versions safely, but blocking prevents writes that might
      // corrupt data the newer app expects.
      let message =
        "Your iCloud data was created by a newer version of RockYou (schema v\(privateSchemaVersion)). "
        + "Update the app to re-enable iCloud sync."
      Log.error(
        "CloudKit",
        "Schema version mismatch (private): found v\(privateSchemaVersion), expected v\(Schema.expectedSchemaVersion). Blocking CloudKit access."
      )
      cloudAccessState = .blocked(foundSchemaVersion: privateSchemaVersion, message: message)
      return false
    }

    // Lower schema version → attempt migration
    let didMigrate = await migrateCloudSchema(
      from: privateSchemaVersion, to: Schema.expectedSchemaVersion)
    if didMigrate {
      cloudAccessState = .ready(schemaVersion: Schema.expectedSchemaVersion)
      return true
    }

    // Migration not implemented or failed
    let message =
      "Your iCloud data is on an older schema (v\(privateSchemaVersion)) and needs migration to v\(Schema.expectedSchemaVersion). "
      + "This app version cannot migrate it yet; iCloud sync is disabled to protect your data."
    cloudAccessState = .blocked(foundSchemaVersion: privateSchemaVersion, message: message)
    return false
  }

  /// Read schema versions from both shared + private zones.
  ///
  /// - Returns: `(sharedSchemaVersion: Int?, privateSchemaVersion: Int?)`
  ///   `nil` means "could not access / could not read".
  ///   (Note: private `nil` can also mean zone/record doesn't exist yet.)
  private func readSchemaVersions() async -> (sharedSchemaVersion: Int?, privateSchemaVersion: Int?)
  {
    // Shared (best-effort). Warnings only when not on Simulator.
    let sharedSchemaVersion: Int? = await {
      do {
        if let (db, zoneID) = try await resolveSharedZoneIfPresent() {
          let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: zoneID)
          return try await fetchSchemaVersion(database: db, rootID: rootID)
        }
        return nil
      } catch {
        if PlatformSecurityPolicy.supportsEndToEndEncryptedAPIs {
          Log.warn(
            "CloudKit",
            "Failed to read RockYouRoot record to check schema (shared): \(error.localizedDescription)"
          )
        }
        return nil
      }
    }()

    // Private (required). Errors should be prominent.
    let privateSchemaVersion: Int? = await {
      do {
        let zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
        let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: zoneID)
        return try await fetchSchemaVersion(
          database: container.privateCloudDatabase, rootID: rootID)
      } catch {
        Log.error(
          "CloudKit",
          "Failed to read RockYouRoot record to check schema (private): \(error.localizedDescription)"
        )
        return nil
      }
    }()

    return (sharedSchemaVersion: sharedSchemaVersion, privateSchemaVersion: privateSchemaVersion)
  }

  private var schemaProbeRetryTask: Task<Void, Never>?

  private func scheduleSchemaProbeRetry() {
    schemaProbeRetryTask?.cancel()
    schemaProbeRetryTask = Task { [weak self] in
      // Simple backoff: retry in ~15s. (We can enhance later.)
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard let self else { return }
      guard !Task.isCancelled else { return }
      if case .blocked = self.cloudAccessState { return }
      _ = await self.ensureCloudSchemaReady()
      if self.isCloudAccessReady {
        await self.ensureSubscriptions()
        await self.refreshFromCloud()
      }
    }
  }

  private func fetchSchemaVersion(database: CKDatabase, rootID: CKRecord.ID) async throws -> Int? {
    do {
      let record = try await database.record(for: rootID)
      if let v = record["schemaVersion"] as? Int { return v }
      if let v = record["schemaVersion"] as? Int64 { return Int(v) }
      return nil
    } catch let error as CKError
      where
      error.code == .unknownItem
      || error.code == .zoneNotFound
      || error.code == .userDeletedZone
    {
      // Treat missing record / missing zone as "no schemaVersion yet".
      return nil
    }
  }

  private func migrateCloudSchema(from: Int, to: Int) async -> Bool {
    // Placeholder: add real migrations later (non-destructive).
    Log.warn("CloudKit", "Migration not implemented: from v\(from) to v\(to)")
    return false
  }

  private func destructiveResetLegacyAndNewZones() async {
    // Best-effort deletes; ignore failures.
    do {
      try await container.privateCloudDatabase.deleteSubscription(
        withID: Schema.legacySubscriptionId)
    } catch {}
    do {
      try await container.privateCloudDatabase.deleteSubscription(
        withID: Schema.privateSubscriptionId)
    } catch {}

    let legacyZoneID = CKRecordZone.ID(
      zoneName: Schema.legacyZoneName, ownerName: CKCurrentUserDefaultName)
    do { _ = try await container.privateCloudDatabase.deleteRecordZone(withID: legacyZoneID) } catch
    {}

    // Also blow away any existing new zone so we start clean.
    let newZoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
    do { _ = try await container.privateCloudDatabase.deleteRecordZone(withID: newZoneID) } catch {}

    // Clear local tokens so we fetch from scratch.
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: DefaultsKey.zoneTokenPrivate)
    defaults.removeObject(forKey: DefaultsKey.zoneTokenShared)
  }

  private func isLikelyCloudSchemaNotDeployed(_ error: Error) -> Bool {
    // In production, attempting to save record types that only exist in the Development schema
    // often surfaces as a generic "BAD_REQUEST" / "server rejected request" style failure.
    //
    // We treat these as non-transient and block CloudKit to avoid thrashing (delete/recreate/retry).
    guard let ck = error as? CKError else { return false }
    switch ck.code {
    case .serverRejectedRequest, .invalidArguments, .incompatibleVersion:
      return true
    default:
      return false
    }
  }

  private func ensureZoneAndRootExistInPrivateDB() async throws {
    let zoneID = CKRecordZone.ID(zoneName: Schema.zoneName, ownerName: CKCurrentUserDefaultName)
    var zoneCreateError: Error?
    do {
      _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
      Log.info("CloudKit", "✅ Zone created/verified: \(Schema.zoneName)")
    } catch {
      // Could be "already exists" or a transient CloudKit failure; we can't reliably distinguish
      // across SDKs, so log it and continue. The root fetch below will tell us if the zone
      // truly doesn't exist.
      Log.warn(
        "CloudKit", "Failed to create/verify zone \(Schema.zoneName): \(error.localizedDescription)"
      )
      zoneCreateError = error
    }

    let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: zoneID)
    do {
      _ = try await container.privateCloudDatabase.record(for: rootID)
    } catch let error as CKError where error.code == .unknownItem {
      let root = CKRecord(recordType: Schema.rootRecordType, recordID: rootID)
      root["schemaVersion"] = Schema.expectedSchemaVersion as CKRecordValue
      root["updatedAt"] = Date() as CKRecordValue
      do {
        _ = try await container.privateCloudDatabase.save(root)
        Log.info("CloudKit", "✅ Root created: \(Schema.rootRecordType)/\(Schema.rootRecordName)")
        return
      } catch {
        Log.warn("CloudKit", "Failed to create root record: \(error.localizedDescription)")
        throw error
      }
    } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone
    {
      Log.warn(
        "CloudKit",
        "Zone \(Schema.zoneName) still does not exist after attempted create: \(error.localizedDescription)"
      )
      // If we have an earlier, more informative error from the zone save (e.g. "Manatee..."),
      // surface that rather than the generic zone-not-found.
      if let zoneCreateError { throw zoneCreateError }
      throw error
    } catch {
      Log.warn("CloudKit", "Failed to verify root record: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: - Account availability

  private func ensureCloudAccountAvailable() async -> Bool {
    let now = Date()
    if let cachedAccountStatus,
      now.timeIntervalSince(lastAccountStatusCheckedAt) < accountStatusCacheTTL
    {
      Log.debug(
        "CloudKit", "Using cached iCloud account status: \(String(describing: cachedAccountStatus))"
      )
      return handleAccountStatus(cachedAccountStatus)
    }

    do {
      let status = try await container.accountStatus()
      cachedAccountStatus = status
      lastAccountStatusCheckedAt = now
      Log.info("CloudKit", "iCloud account status: \(String(describing: status))")
      return handleAccountStatus(status)
    } catch {
      cachedAccountStatus = nil
      lastAccountStatusCheckedAt = now
      if isLikelyCloudAccountUnavailable(error) {
        cloudAccessState = .blocked(
          foundSchemaVersion: nil, message: cloudAccountUnavailableMessage(for: error))
        Log.warn("CloudKit", "iCloud/CloudKit unavailable: \(error.localizedDescription)")
        return false
      }
      Log.warn(
        "CloudKit", "Account status check failed (will retry later): \(error.localizedDescription)")
      cloudAccessState = .unknown
      scheduleSchemaProbeRetry()
      return false
    }
  }

  private func handleAccountStatus(_ status: CKAccountStatus) -> Bool {
    switch status {
    case .available:
      return true
    case .noAccount:
      Log.warn("CloudKit", "iCloud not signed in; blocking CloudKit usage")
      cloudAccessState = .blocked(
        foundSchemaVersion: nil,
        message: "iCloud is not signed in on this device. Sign into iCloud to enable iCloud sync."
      )
      return false
    case .restricted:
      Log.warn("CloudKit", "iCloud restricted; blocking CloudKit usage")
      cloudAccessState = .blocked(
        foundSchemaVersion: nil,
        message: "iCloud access is restricted for this account/device, so iCloud sync is disabled."
      )
      return false
    case .temporarilyUnavailable:
      // In practice (especially on Simulator), accountStatus can report temporarilyUnavailable
      // even while CloudKit operations succeed. Proceed and let real CloudKit operations decide.
      Log.warn(
        "CloudKit", "iCloud temporarily unavailable; proceeding with best-effort CloudKit calls")
      return true
    case .couldNotDetermine:
      Log.warn(
        "CloudKit",
        "Could not determine iCloud account status; proceeding with best-effort CloudKit calls")
      return true
    @unknown default:
      Log.warn("CloudKit", "Unknown iCloud account status; will retry later")
      cloudAccessState = .unknown
      scheduleSchemaProbeRetry()
      return false
    }
  }

  private func isLikelyCloudAccountUnavailable(_ error: Error) -> Bool {
    let ns = error as NSError
    let msg = ns.localizedDescription.lowercased()
    if msg.contains("manatee")
      || msg.contains("not available for the current account")
      || msg.contains("pcs blob")
      || msg.contains("couldn't create new pcs blob")
      || msg.contains("could not create new pcs blob")
      || msg.contains("user key sync")
      || msg.contains("failed user key sync")
    {
      return true
    }
    if let ck = error as? CKError {
      switch ck.code {
      case .notAuthenticated, .permissionFailure, .accountTemporarilyUnavailable:
        return true
      default:
        return false
      }
    }
    return false
  }

  private func cloudAccountUnavailableMessage(for error: Error) -> String {
    let ns = error as NSError
    let msg = ns.localizedDescription
    return
      "iCloud sync is unavailable for the current account/device (\(msg)). "
      + "If you’re on Simulator, sign into iCloud in the Simulator Settings app. "
      + "If the error mentions “Manatee”, enable iCloud Keychain (Settings → Apple Account → iCloud → Passwords & Keychain)."
      + "If it mentions “PCS blob”, iCloud Keychain / end-to-end encryption material isn’t available (common on Simulator)."
      + "If it mentions “user key sync”, iCloud Keychain may still be syncing; leave the device on Wi‑Fi/power for a bit, or toggle Passwords & Keychain off/on."
      + "If this is a managed/restricted Apple ID, CloudKit may be disabled."
  }

  private func ensureSubscriptions() async {
    await ensureDatabaseSubscription(
      database: container.privateCloudDatabase, subscriptionID: Schema.privateSubscriptionId)
    await ensureDatabaseSubscription(
      database: container.sharedCloudDatabase, subscriptionID: Schema.sharedSubscriptionId)
  }

  private func ensureDatabaseSubscription(database: CKDatabase, subscriptionID: String) async {
    let sub = CKDatabaseSubscription(subscriptionID: subscriptionID)
    let info = CKSubscription.NotificationInfo()
    info.shouldSendContentAvailable = true
    sub.notificationInfo = info
    do {
      _ = try await database.save(sub)
    } catch {
      // likely exists or not allowed (shared DB); ignore.
    }
  }

  private func resolveSharedZoneIfPresent() async throws -> (CKDatabase, CKRecordZone.ID)? {
    // Fast-path: if we have an "active household" hint, try it first.
    if let hinted = loadActiveHouseholdSharedZoneID() {
      // Validate by fetching the root record (cheap RecordFetch vs ZoneFetch enumeration).
      let rootID = CKRecord.ID(recordName: Schema.rootRecordName, zoneID: hinted)
      do {
        _ = try await container.sharedCloudDatabase.record(for: rootID)
        // Cache and return.
        sharedZoneCache = .some(zoneID: hinted, checkedAt: Date())
        return (container.sharedCloudDatabase, hinted)
      } catch {
        // Hint is stale (share removed / wrong device state). Clear it and fall back.
        clearActiveHouseholdSharedZoneHint()
      }
    }

    let now = Date()
    switch sharedZoneCache {
    case .some(let zoneID, let checkedAt):
      if now.timeIntervalSince(checkedAt) < sharedZoneCacheTTL {
        return (container.sharedCloudDatabase, zoneID)
      }
    case .none(let checkedAt):
      if now.timeIntervalSince(checkedAt) < sharedZoneCacheTTL {
        return nil
      }
    case .unknown:
      break
    }

    let zones = try await container.sharedCloudDatabase.allRecordZones()
    if let match = zones.first(where: { $0.zoneID.zoneName == Schema.zoneName }) {
      sharedZoneCache = .some(zoneID: match.zoneID, checkedAt: now)
      saveActiveHouseholdSharedZoneHint(zoneID: match.zoneID)
      return (container.sharedCloudDatabase, match.zoneID)
    }

    sharedZoneCache = .none(checkedAt: now)
    return nil
  }

  private func invalidateSharedZoneCache() {
    sharedZoneCache = .unknown
  }

  // MARK: - Active household hint (persisted per-user)

  private func loadActiveHouseholdSharedZoneID() -> CKRecordZone.ID? {
    let defaults = UserDefaults.standard
    guard
      let zoneName = defaults.string(forKey: DefaultsKey.activeHouseholdSharedZoneName),
      let ownerName = defaults.string(forKey: DefaultsKey.activeHouseholdSharedZoneOwnerName),
      !zoneName.isEmpty,
      !ownerName.isEmpty
    else { return nil }
    return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
  }

  private func saveActiveHouseholdSharedZoneHint(zoneID: CKRecordZone.ID) {
    let defaults = UserDefaults.standard
    defaults.set(zoneID.zoneName, forKey: DefaultsKey.activeHouseholdSharedZoneName)
    defaults.set(zoneID.ownerName, forKey: DefaultsKey.activeHouseholdSharedZoneOwnerName)
  }

  private func clearActiveHouseholdSharedZoneHint() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: DefaultsKey.activeHouseholdSharedZoneName)
    defaults.removeObject(forKey: DefaultsKey.activeHouseholdSharedZoneOwnerName)
  }

  private func hydrateActiveHouseholdHintFromPrivateConfig() async {
    // Fetch per-user config from the private DB so all devices on this iCloud account
    // can "auto-activate" the household share without enumerating shared zones.
    do {
      let recID = CKRecord.ID(recordName: Schema.userConfigRecordName)
      let record = try await container.privateCloudDatabase.record(for: recID)
      let zoneName = record[Schema.userConfigActiveSharedZoneNameField] as? String
      let ownerName = record[Schema.userConfigActiveSharedZoneOwnerNameField] as? String
      if let zoneName, let ownerName, !zoneName.isEmpty, !ownerName.isEmpty {
        saveActiveHouseholdSharedZoneHint(
          zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName))
      }
    } catch let error as CKError where error.code == .unknownItem {
      // No config yet.
    } catch {
      // Ignore (offline / not signed in / etc). We'll fall back to cached hint or enumeration.
    }
  }

  private func persistActiveHouseholdHintFromAcceptedShare(metadata: CKShare.Metadata) async {
    // Persist to local defaults.
    guard let id = metadata.hierarchicalRootRecordID else { return }
    let zoneID = id.zoneID
    guard !zoneID.zoneName.isEmpty else { return }

    saveActiveHouseholdSharedZoneHint(zoneID: zoneID)

    // Also persist to the private DB so other devices pick it up.
    do {
      let recID = CKRecord.ID(recordName: Schema.userConfigRecordName)
      let record: CKRecord
      do {
        record = try await container.privateCloudDatabase.record(for: recID)
      } catch let error as CKError where error.code == .unknownItem {
        record = CKRecord(recordType: Schema.userConfigRecordType, recordID: recID)
      }

      record[Schema.userConfigActiveSharedZoneNameField] = zoneID.zoneName as CKRecordValue
      record[Schema.userConfigActiveSharedZoneOwnerNameField] = zoneID.ownerName as CKRecordValue
      record[Schema.userConfigUpdatedAtField] = Date() as CKRecordValue
      _ = try await container.privateCloudDatabase.save(record)
    } catch {
      // Non-fatal: local hint is still enough for this device.
    }
  }

  // MARK: - Zone change fetch

  private func fetchZoneChanges(
    database: CKDatabase, zoneID: CKRecordZone.ID, defaultsTokenKey: String
  ) async {
    let previousToken = loadZoneToken(forKey: defaultsTokenKey)

    let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
      previousServerChangeToken: previousToken)
    config.resultsLimit = 200

    let op = CKFetchRecordZoneChangesOperation(
      recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: config])
    op.fetchAllChanges = true

    op.recordWasChangedBlock = { [weak self] recordID, recordResult in
      guard let self else { return }
      if case .success(let record) = recordResult {
        Task { @MainActor in
          self.applyChangedRecord(record)
        }
      }
    }

    op.recordWithIDWasDeletedBlock = { [weak self] recordID, recordType in
      guard let self else { return }
      Task { @MainActor in
        self.applyDeletedRecord(recordID: recordID, recordType: recordType)
      }
    }

    op.recordZoneChangeTokensUpdatedBlock = { [weak self] zoneID, token, _ in
      guard let self else { return }
      Task { @MainActor in
        self.saveZoneToken(token, forKey: defaultsTokenKey)
      }
    }

    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
      op.fetchRecordZoneChangesResultBlock = { result in
        Task { @MainActor in
          // Tokens are persisted incrementally via recordZoneChangeTokensUpdatedBlock.
          // The result here is just completion/success/failure.
          if case .failure(let error) = result {
            Log.warn("CloudKit", "Zone changes fetch failed: \(error.localizedDescription)")
          }
          cont.resume(returning: ())
        }
      }
      database.add(op)
    }
  }

  private func applyChangedRecord(_ record: CKRecord) {
    switch record.recordType {
    case Schema.pairingRecordType:
      guard let tvId = record["tvId"] as? String,
        let streamerId = record["streamerId"] as? String
      else { return }
      var pairing = TVPairing(tvId: tvId, streamerId: streamerId)
      pairing.tvName = record["tvName"] as? String
      pairing.streamerName = record["streamerName"] as? String

      var dict = Dictionary(uniqueKeysWithValues: cachedPairings.map { ($0.tvId, $0) })
      dict[tvId] = pairing
      cachedPairings = Array(dict.values)
      savePairingsCache()
      onPairingsUpdated?(cachedPairings)

    case Schema.mruRecordType:
      guard let deviceId = record["deviceId"] as? String,
        let appId = record["appId"] as? String,
        let lastUsedAt = record["lastUsedAt"] as? Date
      else { return }

      var map = cachedMRUByDevice[deviceId] ?? [:]
      map[appId] = lastUsedAt
      cachedMRUByDevice[deviceId] = map
      saveMRUCache()
      AppCacheManager.shared.setMRU(map, for: deviceId)
      onMRUUpdated?(deviceId, map)

    default:
      break
    }
  }

  private func applyDeletedRecord(recordID: CKRecord.ID, recordType: String) {
    switch recordType {
    case Schema.pairingRecordType:
      // We don't have tvId reliably from recordID; do a cheap refetch later.
      scheduleRefreshDebounced()

    case Schema.mruRecordType:
      scheduleRefreshDebounced()

    default:
      break
    }
  }

  private func scheduleRefreshDebounced() {
    guard isCloudAccessReady else { return }
    refreshDebounceTask?.cancel()
    refreshDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1s debounce
      guard let self else { return }
      guard !Task.isCancelled else { return }
      await self.refreshFromCloud(force: true)
    }
  }

  // MARK: - Local caching

  private func loadCaches() {
    let defaults = UserDefaults.standard

    if let data = defaults.data(forKey: DefaultsKey.cachedPairings),
      let decoded = try? JSONDecoder().decode([TVPairing].self, from: data)
    {
      cachedPairings = decoded
    }

    if let data = defaults.data(forKey: DefaultsKey.cachedMRU),
      let decoded = try? JSONDecoder().decode([String: [String: TimeInterval]].self, from: data)
    {
      cachedMRUByDevice = decoded.mapValues { inner in
        inner.mapValues { Date(timeIntervalSince1970: $0) }
      }
    }

    // Bridge cached MRU into AppCacheManager so AppStrip can sort immediately at launch.
    for (deviceId, map) in cachedMRUByDevice {
      AppCacheManager.shared.setMRU(map, for: deviceId)
    }
  }

  private func savePairingsCache() {
    let defaults = UserDefaults.standard
    if let data = try? JSONEncoder().encode(cachedPairings) {
      defaults.set(data, forKey: DefaultsKey.cachedPairings)
    }
  }

  private func saveMRUCache() {
    let defaults = UserDefaults.standard
    let enc: [String: [String: TimeInterval]] = cachedMRUByDevice.mapValues { inner in
      inner.mapValues { $0.timeIntervalSince1970 }
    }
    if let data = try? JSONEncoder().encode(enc) {
      defaults.set(data, forKey: DefaultsKey.cachedMRU)
    }
  }

  private func loadZoneToken(forKey key: String) -> CKServerChangeToken? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
  }

  private func saveZoneToken(_ token: CKServerChangeToken?, forKey key: String) {
    guard let token else {
      UserDefaults.standard.removeObject(forKey: key)
      return
    }
    if let data = try? NSKeyedArchiver.archivedData(
      withRootObject: token, requiringSecureCoding: true)
    {
      UserDefaults.standard.set(data, forKey: key)
    }
  }
}
