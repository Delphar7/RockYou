//
//  RokuDiscoveryService.swift
//  RockYou
//
//  Network discovery service for Roku devices.
//  Supports multiple discovery methods via provider pattern.
//  Streaming model: devices appear in UI as they're discovered.
//

import Foundation
import Network
import Observation
import os.lock

// MARK: - Discovery Provider Protocol
// Note: DeviceInfo is defined in Shared/Devices/DeviceInfo.swift
/// Providers call `onDeviceFound` for each device as it's discovered (streaming model)
protocol RokuDiscoveryProvider: Sendable {
  var name: String { get }
  func discover(timeout: TimeInterval, onDeviceFound: @escaping @Sendable (DeviceInfo) -> Void)
    async throws
}

// MARK: - Discovery Method
enum DiscoveryMethod {
  case ssdpNative  // NWConnectionGroup - Apple's native multicast API
  case subnetScan  // Brute-force HTTP probe (backup)
  case nativeWithFallback  // Try native first, fall back to subnet scan
}

// MARK: - Discovery Service
/// Observable service that discovers Roku devices on the network.
/// - Automatically starts discovery on init
/// - Refreshes every 30 seconds
/// - Maintains a cache that observers can watch
@Observable
@MainActor
final class RokuDiscoveryService {
  // MARK: - Published State (Cache)
  private(set) var discoveredDevices: [DeviceInfo] = []
  private(set) var isScanning: Bool = false
  private(set) var lastError: String?
  private(set) var lastUsedMethod: String = ""
  private(set) var lastRefreshTime: Date?

  // MARK: - Filtered Access
  var tvs: [DeviceInfo] { discoveredDevices.filter { $0.isTV } }
  var streamingDevices: [DeviceInfo] { discoveredDevices.filter { $0.isStreamingDevice } }

  // MARK: - Configuration
  var method: DiscoveryMethod = .nativeWithFallback
  var timeout: TimeInterval = 5.0
  var autoRefreshInterval: TimeInterval = 30.0
  var autoRefreshEnabled: Bool = true

  // MARK: - Change Notification
  /// Called when the device list changes (additions only, not removals)
  var onDevicesChanged: (([DeviceInfo]) -> Void)?

  // MARK: - Private
  private var discoveryTask: Task<Void, Never>?
  private var autoRefreshTask: Task<Void, Never>?
  private let nativeProvider = NWConnectionGroupDiscoveryProvider()
  private let subnetProvider = SubnetScanDiscoveryProvider()
  private static let debugTestRokuTVId = "debug-test-roku-tv"

  // Coalesce frequent updates (SSDP/subnet can produce bursts; saving + notifying per-device is expensive).
  private var pendingDeviceListFlushTask: Task<Void, Never>?
  private var deviceListDirty: Bool = false

  // MARK: - Cache Persistence
  private static let cacheKey = "com.rockyou.devicecache"

  /// Load device cache from persistent storage
  private func loadCache() {
    DebugBuild.syncCurrentAppPreferences()

    guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
      let cached = try? JSONDecoder().decode([DeviceInfo].self, from: data)
    else {
      DebugBuild.run {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
          Log.warn("Discovery", "Failed to decode device cache (len=\(data.count))")
        }
      }
      return
    }

    // Defensive: in the past we could create "devices" without a stable Roku identifier
    // (no serial-number / device-id), which generated a random UUID and could linger in cache
    // as a "ghost" offline Roku Device. Purge those immediately.
    let filtered = cached.filter { UUID(uuidString: $0.id) == nil }
    let purged = cached.count - filtered.count
    discoveredDevices = filtered
    if purged > 0 {
      Log.warn("Discovery", "Purged \(purged) invalid cached device(s) (generated UUID ids)")
      saveCache()
    }
    Log.info("Discovery", "Loaded \(discoveredDevices.count) device(s) from cache")
    // Note: Don't prune here - wait for discovery to give stale devices a chance to respond
  }

  /// Save device cache to persistent storage
  private func saveCache() {
    guard let data = try? JSONEncoder().encode(discoveredDevices) else { return }
    UserDefaults.standard.set(data, forKey: Self.cacheKey)
    DebugBuild.flushUserDefaults()
  }

  private func scheduleDeviceListFlush(reason: String) {
    _ = reason
    deviceListDirty = true
    pendingDeviceListFlushTask?.cancel()
    pendingDeviceListFlushTask = Task { @MainActor in
      // Small debounce to coalesce bursts of discoveries.
      try? await Task.sleep(nanoseconds: 150_000_000)
      guard !Task.isCancelled else { return }
      flushDeviceListNow()
    }
  }

  private func flushDeviceListNow() {
    guard deviceListDirty else { return }
    deviceListDirty = false
    saveCache()
    onDevicesChanged?(discoveredDevices)
  }

  /// Purge devices not seen in 72+ hours
  private func pruneOrphanedDevices() {
    let before = discoveredDevices.count
    discoveredDevices.removeAll { $0.isOrphaned }
    let pruned = before - discoveredDevices.count
    if pruned > 0 {
      Log.info("Discovery", "Purged \(pruned) orphaned device(s) (not seen in 72+ hours)")
      saveCache()
    }
  }

  private func reconcileMissingDevicesAfterScan(seenIds: Set<String>, isManual: Bool) async {
    for device in discoveredDevices {
      let shouldCheck: Bool = {
        if isManual { return !seenIds.contains(device.id) }
        return device.isStale
      }()

      guard shouldCheck else { continue }
      guard let deviceInfo = await fetchDeviceInfo(ip: device.ipAddress, port: device.port) else {
        DeviceStateManager.shared.setPowerMode(.off, for: device.id)
        continue
      }

      DeviceStateManager.shared.setPowerMode(
        PowerMode.fromECPPowerMode(deviceInfo["power-mode"]), for: device.id)

      guard
        let fresh = DeviceInfoParser.createDevice(
          from: deviceInfo, ip: device.ipAddress, port: device.port)
      else { continue }
      guard fresh.id == device.id else {
        Log.warn(
          "Discovery",
          "Device-info response ID mismatch at \(device.ipAddress): cached=\(device.id), response=\(fresh.id)"
        )
        continue
      }

      guard let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) else {
        continue
      }
      var updated = fresh
      updated.idx = discoveredDevices[index].idx
      discoveredDevices[index] = updated
      saveCache()
    }
  }

  private func fetchDeviceInfo(ip: String, port: Int) async -> [String: String]? {
    guard let url = URL(string: "http://\(ip):\(port)/query/device-info") else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = 2.0

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        return nil
      }
      return DeviceInfoParser.parse(data)
    } catch {
      return nil
    }
  }

  func debugInjectTestRokuTV() {
      guard DebugBuild.isEnabled else { return }
      let device = DeviceInfo(
        id: Self.debugTestRokuTVId,
        name: "Test Roku TV",
        location: "Injected",
        ipAddress: "192.0.2.123",
        isTV: true,
        model: "Debug Model",
        port: 8060,
        lastSeen: Date()
      )

      if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
        discoveredDevices[index] = device
      } else {
        discoveredDevices.append(device)
      }

      saveCache()
      DeviceStateManager.shared.setPowerMode(.on, for: device.id)
      onDevicesChanged?(discoveredDevices)
      Log.info("Discovery", "🧪 Injected debug test Roku TV")
    }

    func debugExpireTestRokuTV() {
      guard DebugBuild.isEnabled else { return }
      guard let index = discoveredDevices.firstIndex(where: { $0.id == Self.debugTestRokuTVId })
      else { return }

      discoveredDevices[index].lastSeen = Date().addingTimeInterval(-7 * 24 * 60 * 60)
      saveCache()
      DeviceStateManager.shared.setPowerMode(.off, for: Self.debugTestRokuTVId)
      onDevicesChanged?(discoveredDevices)
      Log.info("Discovery", "🧪 Expired debug test Roku TV (lastSeen = 7 days ago)")
    }

  // MARK: - Initialization

  init() {
    loadCache()  // Restore cached devices first for instant UI

    // Query power states for cached devices immediately
    if !discoveredDevices.isEmpty {
      Task {
        await RokuECPClient.shared.queryAllDevicePowerStates(discoveredDevices)
      }
    }

    startDiscovery()
    startAutoRefresh()
  }

  // MARK: - Public API

  /// Trigger an immediate refresh (rescans without clearing device list)
  func refresh() {
    stopDiscovery()
    startDiscovery(isManual: true)
  }

  /// Remove a device from the persisted discovery cache.
  /// This does not affect the actual network device, only the locally cached list.
  func removeDeviceFromCache(deviceId: String) {
    let before = discoveredDevices.count
    discoveredDevices.removeAll { $0.id == deviceId }
    let removed = before - discoveredDevices.count
    guard removed > 0 else { return }
    saveCache()
    DeviceStateManager.shared.setPowerMode(.off, for: deviceId)
    onDevicesChanged?(discoveredDevices)
  }

  /// Start discovery (merges new devices into existing cache)
  func startDiscovery(isManual: Bool = false) {
    guard !isScanning else { return }

    isScanning = true
    lastError = nil

    discoveryTask = Task {
      await performDiscovery(isManual: isManual)
    }
  }

  /// Stop current discovery scan
  func stopDiscovery() {
    isScanning = false
    discoveryTask?.cancel()
    discoveryTask = nil
  }

  /// Stop auto-refresh timer
  func stopAutoRefresh() {
    autoRefreshTask?.cancel()
    autoRefreshTask = nil
  }

  /// Start auto-refresh timer
  func startAutoRefresh() {
    stopAutoRefresh()
    guard autoRefreshEnabled else { return }

    autoRefreshTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(autoRefreshInterval * 1_000_000_000))
        guard !Task.isCancelled else { break }
        startDiscovery()
      }
    }
  }

  // MARK: - Discovery Implementation

  private func performDiscovery(isManual: Bool) async {
    let runStartedAt = Date()

    // Swift 6: avoid mutating captured vars from concurrently-executing closures.
    // Use async-safe locking around the shared state instead.
    let seenIdsLock = OSAllocatedUnfairLock(initialState: Set<String>())
    let ssdpSeenIdsLock = OSAllocatedUnfairLock(initialState: Set<String>())
    let subnetSeenIdsLock = OSAllocatedUnfairLock(initialState: Set<String>())
    let updateTasksLock = OSAllocatedUnfairLock(initialState: [Task<Void, Never>]())

    enum DiscoverySource: Sendable {
      case ssdp
      case subnet
    }

    // Core handler that adds/updates devices in cache (logs only new devices)
    let handleDeviceFound: @Sendable (DeviceInfo) -> Void = { device in
      let updateTask = Task { @MainActor in
        // `self` is a long-lived singleton; capture it strongly. (A nested `[weak self]` here only
        // conflicted with the strong capture already present in the enclosing scope.)
        // Update existing or add new
        if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
          let existing = self.discoveredDevices[index]
          // Existing device - update with fresh data
          self.discoveredDevices[index] = device
          // Notify if IP changed (UI may need to reconnect)
          if existing.ipAddress != device.ipAddress {
            Log.info(
              "Discovery",
              "📡 \(device.name) IP changed: \(existing.ipAddress) → \(device.ipAddress)")
          }
          self.scheduleDeviceListFlush(reason: "update")
        } else {
          // NEW device - log it and notify
          let typeIcon = device.isTV ? "📺" : "📡"
          Log.info(
            "Discovery",
            "Discovered \(typeIcon) \(device.deviceType.rawValue): \(device.name) at \(device.ipAddress)"
          )
          self.discoveredDevices.append(device)
          self.scheduleDeviceListFlush(reason: "new")
        }
      }

      updateTasksLock.withLock { $0.append(updateTask) }
    }

    // Wrapper that attributes findings to a source, then forwards to core handler.
    func makeOnDeviceFound(source: DiscoverySource) -> @Sendable (DeviceInfo) -> Void {
      { device in
        _ = seenIdsLock.withLock { $0.insert(device.id) }
        switch source {
        case .ssdp:
          _ = ssdpSeenIdsLock.withLock { $0.insert(device.id) }
        case .subnet:
          _ = subnetSeenIdsLock.withLock { $0.insert(device.id) }
        }
        handleDeviceFound(device)
      }
    }

    func awaitPendingUpdates() async {
      let tasksToAwait: [Task<Void, Never>] = {
        updateTasksLock.withLock { tasks in
          let drained = tasks
          tasks.removeAll(keepingCapacity: true)
          return drained
        }
      }()
      for task in tasksToAwait {
        await task.value
      }
    }

    func snapshotSeenIds() -> Set<String> {
      seenIdsLock.withLock { $0 }
    }

    func snapshotSSDPSeenIds() -> Set<String> {
      ssdpSeenIdsLock.withLock { $0 }
    }

    func snapshotSubnetSeenIds() -> Set<String> {
      subnetSeenIdsLock.withLock { $0 }
    }

    do {
      switch method {
      case .ssdpNative:
        // Using NWConnectionGroup (native) discovery
        lastUsedMethod = nativeProvider.name
        try await nativeProvider.discover(
          timeout: timeout, onDeviceFound: makeOnDeviceFound(source: .ssdp))

      case .subnetScan:
        // Using subnet scan discovery
        lastUsedMethod = subnetProvider.name
        try await subnetProvider.discover(
          timeout: timeout, onDeviceFound: makeOnDeviceFound(source: .subnet))

      case .nativeWithFallback:
        // Try NWConnectionGroup first (cleanest)
        lastUsedMethod = nativeProvider.name
        try await nativeProvider.discover(
          timeout: timeout, onDeviceFound: makeOnDeviceFound(source: .ssdp))

        await awaitPendingUpdates()
        let foundAnyViaNative = !snapshotSeenIds().isEmpty
        if !foundAnyViaNative && !Task.isCancelled {
          // Fall back to subnet scan
          Log.debug("Discovery", "SSDP found nothing, trying subnet scan...")
          lastUsedMethod = subnetProvider.name
          try await subnetProvider.discover(
            timeout: timeout, onDeviceFound: makeOnDeviceFound(source: .subnet))
        }
      }

      if !Task.isCancelled {
        await awaitPendingUpdates()
        await MainActor.run { [weak self] in
          self?.flushDeviceListNow()
        }
        lastRefreshTime = Date()
        let seen = snapshotSeenIds()
        let ssdpSeen = snapshotSSDPSeenIds()
        let subnetSeen = snapshotSubnetSeenIds()

        await reconcileMissingDevicesAfterScan(seenIds: seen, isManual: isManual)
        pruneOrphanedDevices()
        let tvCount = tvs.count
        let streamingCount = streamingDevices.count
        Log.info(
          "Discovery",
          "Complete via \(lastUsedMethod). Cache has \(tvCount) TV(s), \(streamingCount) streaming device(s)"
        )

        // Simple per-run metrics (no persistence)
        let duration = Date().timeIntervalSince(runStartedAt)
        let subnetOnly = subnetSeen.subtracting(ssdpSeen)
        Log.info(
          "Discovery",
          String(
            format:
              "Metrics: ssdp=%d subnet=%d subnetOnly=%d duration=%.2fs",
            ssdpSeen.count, subnetSeen.count, subnetOnly.count, duration
          )
        )

        // Query power states for all discovered devices (populates DeviceStateManager)
        if !seen.isEmpty {
          let seenDevices = discoveredDevices.filter { seen.contains($0.id) }
          await RokuECPClient.shared.queryAllDevicePowerStates(seenDevices)
        }
      }
    } catch {
      lastError = error.localizedDescription
      Log.error("Discovery", "Failed: \(error.localizedDescription)")
    }

    isScanning = false
  }
}

// MARK: - Singleton
extension RokuDiscoveryService {
  static let shared = RokuDiscoveryService()
}

// MARK: - Thread-safe location tracker (for concurrent SSDP responses)
private actor SeenLocations {
  private var locations: Set<String> = []

  /// Returns true if this is a new location (atomically inserts and checks)
  func insertIfNew(_ location: String) -> Bool {
    let (inserted, _) = locations.insert(location)
    return inserted
  }
}

// MARK: - Thread-safe interrogation task tracker (for SSDP interrogation tasks)
private final class InterrogationTaskTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [Task<Void, Never>] = []

  func add(_ task: Task<Void, Never>) {
    lock.lock()
    tasks.append(task)
    lock.unlock()
  }

  func drain() -> [Task<Void, Never>] {
    lock.lock()
    defer { lock.unlock() }
    let drained = tasks
    tasks.removeAll(keepingCapacity: true)
    return drained
  }
}

// MARK: - NWConnectionGroup Discovery Provider (Native Apple Multicast)
/// Uses Apple's Network.framework NWConnectionGroup for proper async multicast.
/// See: https://developer.apple.com/news/?id=0oi77447
/// Note: Requires com.apple.developer.networking.multicast entitlement on physical devices.
struct NWConnectionGroupDiscoveryProvider: RokuDiscoveryProvider {
  let name = "NWConnectionGroup"

  private let ssdpAddress = "239.255.255.250"
  private let ssdpPort: UInt16 = 1900
  private let searchTarget = "roku:ecp"

  func discover(timeout: TimeInterval, onDeviceFound: @escaping @Sendable (DeviceInfo) -> Void)
    async throws
  {

    // Create multicast group for SSDP
    let multicastGroup: NWMulticastGroup
    do {
      multicastGroup = try NWMulticastGroup(for: [
        .hostPort(host: NWEndpoint.Host(ssdpAddress), port: NWEndpoint.Port(rawValue: ssdpPort)!)
      ])
    } catch {
      Log.error("Discovery", "Failed to create multicast group: \(error.localizedDescription)")
      throw error
    }

    let group = NWConnectionGroup(with: multicastGroup, using: .udp)
    let seenLocations = SeenLocations()
    let interrogationTasks = InterrogationTaskTracker()

    // Handle incoming SSDP responses
    group.setReceiveHandler(maximumMessageSize: 2048, rejectOversizedMessages: true) {
      _, content, _ in
      guard let data = content, let response = String(data: data, encoding: .utf8) else { return }
      guard let location = self.parseLocationHeader(response) else { return }

      let task = Task {
        if await seenLocations.insertIfNew(location) {
          await self.interrogateDevice(location: location, onDeviceFound: onDeviceFound)
        }
      }
      interrogationTasks.add(task)
    }

    // Handle state changes
    group.stateUpdateHandler = { state in
      switch state {
      case .ready:
        // Send M-SEARCH request
        let mSearch =
          "M-SEARCH * HTTP/1.1\r\nHOST: \(self.ssdpAddress):\(self.ssdpPort)\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: \(self.searchTarget)\r\n\r\n"
        let data = Data(mSearch.utf8)
        group.send(content: data) { error in
          if let error = error {
            Log.error("Discovery", "Failed to send M-SEARCH: \(error.localizedDescription)")
          }
        }
      case .failed(let error):
        Log.error("Discovery", "NWConnectionGroup failed: \(error.localizedDescription)")
      default:
        break
      }
    }

    // Start the group and wait for timeout
    group.start(queue: .global(qos: .userInitiated))
    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

    // Stop accepting new responses, cancel the group, then drain outstanding interrogations.
    group.cancel()

    var sawEmptyDrain = false
    while true {
      let tasks = interrogationTasks.drain()
      if tasks.isEmpty {
        if sawEmptyDrain { break }
        sawEmptyDrain = true
        await Task.yield()
        continue
      }
      sawEmptyDrain = false
      for task in tasks {
        await task.value
      }
    }
  }

  private func parseLocationHeader(_ response: String) -> String? {
    for line in response.components(separatedBy: "\r\n") {
      if line.lowercased().hasPrefix("location:") {
        return line.dropFirst(9).trimmingCharacters(in: .whitespaces)
      }
    }
    return nil
  }

  private func interrogateDevice(
    location: String, onDeviceFound: @escaping @Sendable (DeviceInfo) -> Void
  ) async {
    guard let url = URL(string: location), let host = url.host else { return }
    let port = url.port ?? 8060

    guard let infoURL = URL(string: "http://\(host):\(port)/query/device-info") else { return }

    do {
      var request = URLRequest(url: infoURL)
      request.timeoutInterval = 2.0

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        return
      }

      let info = DeviceInfoParser.parse(data)
      if let device = DeviceInfoParser.createDevice(from: info, ip: host, port: port) {
        onDeviceFound(device)
      }
    } catch {
      Log.warn("Discovery", "Interrogation failed for \(host): \(error.localizedDescription)")
    }
  }
}

// MARK: - Subnet Scan Discovery Provider (HTTP Backup)
struct SubnetScanDiscoveryProvider: RokuDiscoveryProvider {
  let name = "Subnet Scan"
  private let maxConcurrentProbes = 32

  func discover(timeout: TimeInterval, onDeviceFound: @escaping @Sendable (DeviceInfo) -> Void)
    async throws
  {
    // Starting subnet scan (fallback method)

    let subnets = getLocalSubnets()
    guard !subnets.isEmpty else {
      throw DiscoveryError.noNetworkInterfaces
    }

    Log.debug("Discovery", "Scanning subnet(s): \(subnets.joined(separator: ", "))")

    await withTaskGroup(of: Void.self) { group in
      var inFlight = 0

      for subnet in subnets {
        for i in 1...254 {
          let ip = "\(subnet).\(i)"
          group.addTask { [subnet] in
            _ = subnet  // keep capture explicit; avoids accidental self capture changes later
            await self.probeAndInterrogate(ip: ip, onDeviceFound: onDeviceFound)
          }
          inFlight += 1

          if inFlight >= maxConcurrentProbes {
            _ = await group.next()
            inFlight -= 1
          }
        }
      }

      while inFlight > 0 {
        _ = await group.next()
        inFlight -= 1
      }
    }

    // Subnet scan complete
  }

  private func getLocalSubnets() -> [String] {
    var subnets: Set<String> = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
      let interface = ptr.pointee
      let addrFamily = interface.ifa_addr.pointee.sa_family

      if addrFamily == UInt8(AF_INET) {
        let name = String(cString: interface.ifa_name)
        if name.hasPrefix("en") {
          var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
          if getnameinfo(
            interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0
          {
            let ip = String(cString: hostname)
            // Skip addresses that are never useful for Roku discovery and generate huge noise.
            // - 127.0.0.0/8: loopback
            // - 169.254.0.0/16: IPv4 link-local (common on inactive interfaces)
            // - 0.0.0.0: invalid
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") || ip == "0.0.0.0" {
              continue
            }
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
              let subnet = "\(parts[0]).\(parts[1]).\(parts[2])"
              subnets.insert(subnet)
              // Found interface \(name): \(ip)
            }
          }
        }
      }
    }
    return Array(subnets)
  }

  private func probeAndInterrogate(
    ip: String, onDeviceFound: @escaping @Sendable (DeviceInfo) -> Void
  ) async {
    guard let url = URL(string: "http://\(ip):8060/query/device-info") else { return }

    var request = URLRequest(url: url)
    request.timeoutInterval = 1.0

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        return
      }

      let info = DeviceInfoParser.parse(data)
      if let device = DeviceInfoParser.createDevice(from: info, ip: ip, port: 8060) {
        onDeviceFound(device)
      }
    } catch {
      // Expected for most IPs
    }
  }
}

// MARK: - Device Info Parser (shared)
enum DeviceInfoParser {
  static func parse(_ data: Data) -> [String: String] {
    guard let xmlString = String(data: data, encoding: .utf8) else { return [:] }
    // Fast sanity check: Roku's endpoint wraps fields under <device-info>.
    guard xmlString.contains("<device-info") else { return [:] }
    do {
      return try RokuXMLFieldParser.parseAllFields(data)
    } catch {
      return [:]
    }
  }

  static func createDevice(from info: [String: String], ip: String, port: Int) -> DeviceInfo? {
    let serial = info["serial-number"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let deviceId = info["device-id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let stableId: String? = {
      if let serial, !serial.isEmpty { return serial }
      if let deviceId, !deviceId.isEmpty { return deviceId }
      return nil
    }()

    // If we don't have a stable identifier, this is very likely a false-positive HTTP 200 from
    // some other device on the subnet (or a malformed response). Do not create a "Roku Device"
    // with a random UUID, since it will linger in cache as an offline ghost.
    guard let id = stableId else {
      DebugBuild.run {
        Log.warn("Discovery", "Ignoring device-info from \(ip): missing serial-number/device-id")
      }
      return nil
    }

    let name = info["user-device-name"] ?? info["friendly-device-name"] ?? "Roku Device"
    let location: String? = {
      guard let loc = info["user-device-location"], !loc.isEmpty else { return nil }
      return loc
    }()
    let model = info["friendly-model-name"] ?? info["model-name"] ?? "Unknown Model"
    let isTV = info["is-tv"]?.lowercased() == "true"

    return DeviceInfo(
      id: id,
      name: name,
      location: location,
      ipAddress: ip,
      isTV: isTV,
      model: model,
      properties: info,
      port: port,
      lastSeen: Date()
    )
  }
}

// MARK: - Discovery Errors
enum DiscoveryError: LocalizedError {
  case noNetworkInterfaces

  var errorDescription: String? {
    switch self {
    case .noNetworkInterfaces:
      return "No network interfaces found"
    }
  }
}
