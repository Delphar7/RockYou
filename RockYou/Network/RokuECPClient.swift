//
//  RokuECPClient.swift
//  RockYou
//
//  High-level client for Roku External Control Protocol.
//  Uses ECP-2 (WebSocket) for all commands - this bypasses "Limited Mode"
//  restrictions and provides real-time event notifications.
//
//  ⚠️ HTTP ECP-1 methods are kept as fallback ONLY and should be avoided.
//  Many Roku devices return 403 Forbidden for HTTP requests.
//

import Foundation

// MARK: - Roku Device Properties
/// All scraped properties from a Roku device
struct RokuDeviceProperties: Sendable {
  let deviceId: String
  let fetchedAt: Date

  // Raw property bags from each endpoint
  let deviceInfo: [String: String]
  let installedApps: [RokuApp]
  let activeApp: RokuApp?
  let mediaPlayerState: [String: String]?

  var summary: String {
    var lines: [String] = []
    lines.append("═══════════════════════════════════════")
    lines.append("Device: \(deviceInfo["user-device-name"] ?? deviceInfo["friendly-device-name"] ?? "Unknown")")
    lines.append("Model: \(deviceInfo["friendly-model-name"] ?? deviceInfo["model-name"] ?? "Unknown")")
    lines.append("═══════════════════════════════════════")
    lines.append("")
    lines.append("── Device Info ──")
    for (key, value) in deviceInfo.sorted(by: { $0.key < $1.key }) {
      lines.append("  \(key): \(value)")
    }
    lines.append("")
    lines.append("── Installed Apps (\(installedApps.count)) ──")
    for app in installedApps.prefix(10) {
      lines.append("  [\(app.id)] \(app.name)\(app.version.map { " v\($0)" } ?? "")")
    }
    if installedApps.count > 10 {
      lines.append("  ... and \(installedApps.count - 10) more")
    }
    lines.append("")
    if let active = activeApp {
      lines.append("── Active App ──")
      lines.append("  \(active.name) [\(active.id)]")
    }
    if let media = mediaPlayerState, !media.isEmpty {
      lines.append("")
      lines.append("── Media Player ──")
      for (key, value) in media.sorted(by: { $0.key < $1.key }) {
        lines.append("  \(key): \(value)")
      }
    }
    lines.append("═══════════════════════════════════════")
    return lines.joined(separator: "\n")
  }
}

// MARK: - ECP Client
// Note: DeviceStateManager is now in Shared/DeviceStateManager.swift
actor RokuECPClient {
  static let shared = RokuECPClient()

  // MARK: - Text Edit (ECP-2 keyboard)

  struct TexteditState: Sendable, Equatable {
    let texteditId: String
    let text: String
  }

  // MARK: - ECP-1 HTTP is disabled by default
  //
  // ⚠️ IMPORTANT:
  // This app should operate using ECP-2 (WebSocket) only. Many Roku devices run in
  // "Limited Mode" where HTTP (ECP-1) returns 403 and silently breaks control flows.
  //
  // If we ever need to intentionally enable HTTP fallback, add the build setting:
  //   OTHER_SWIFT_FLAGS = -DROCKYOU_ENABLE_ECP1_FALLBACK
  //
  // Until then, all ECP-1 helpers are compiled out / marked unavailable so we can't
  // accidentally call them in new code.

  // Cache of fetched properties by device ID
  private var propertiesCache: [String: RokuDeviceProperties] = [:]

  // Best-known device info by device ID (IP can change via DHCP)
  private var devicesById: [String: DeviceInfo] = [:]

  // WebSocket connection pool (keyed by device IP)
  private var webSocketClients: [String: RokuWebSocketClient] = [:]
  // Single-flight WebSocket connection attempts by device IP.
  // Prevents multiple concurrent reconnects (icons, polling, keypress) from fighting.
  private var connectTasksByIP: [String: Task<Bool, Never>] = [:]

  // Track which devices are in "limited mode" (HTTP returned 403)
  private var limitedModeDevices: Set<String> = []

  // Device IPs currently being torn down and reconnected (gates key sends).
  private var reconnectingIPs: Set<String> = []

  // Media progress ticking while playing (ECP-2 does not send progress updates)
  private var mediaProgressTasks: [String: Task<Void, Never>] = [:]
  private var mediaResyncTasks: [String: Task<Void, Never>] = [:]
  private var mediaProgressEnabledDeviceIds: Set<String> = []

  // MARK: - Per-silo operation routing (pair-aware)

  /// A "silo" represents the user's selected controllable thing.
  /// Today that maps to the TV id (selectionId) which may have an attached streamer.
  private var siloTails: [String: Task<Void, Never>] = [:]

  private struct WakeState {
    var startedAt: Date
    var deadline: Date
    var refreshSent: Bool
    var cancelWait: Bool
    var requiredDeviceIds: Set<String>
  }

  private var wakeStates: [String: WakeState] = [:]
  private var wakeTasks: [String: Task<Bool, Never>] = [:]

  // App list refresh (MRU ordering) for active device(s)
  private var appListRefreshEnabledDeviceIds: Set<String> = []
  private var appListRefreshTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  // MARK: - Textedit snapshot fetcher install (for debounce/resync)

  private func installTextEditSnapshotFetcherIfNeeded() async {
    await MainActor.run {
      RokuTextEditStateManager.shared.installSnapshotFetcherIfNeeded { deviceId in
        await RokuECPClient.shared.fetchTexteditSnapshot(deviceId: deviceId)
      }
    }
  }

  /// Fetch a best-effort textedit snapshot for a device id.
  /// Used by `RokuTextEditStateManager` when notifications omit the current text.
  private func fetchTexteditSnapshot(deviceId: String) async -> RokuTextEditState? {
    let device: DeviceInfo
    if let known = devicesById[deviceId] {
      device = known
    } else if let discovered = await MainActor.run(body: {
      RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
    }) {
      device = discovered
    } else {
      return nil
    }

    guard await ensureConnected(to: device, primeState: false),
          let client = webSocketClients[device.ipAddress],
          await client.isConnected
    else { return nil }

    do {
      guard let data = try await client.queryTexteditState(),
            let payload = String(data: data, encoding: .utf8),
            let parsed = Self.parseTexteditState(xml: payload)
      else { return nil }

      if parsed.texteditId.isEmpty || parsed.texteditId == "none" { return nil }
      return RokuTextEditState(texteditId: parsed.texteditId, text: parsed.text)
    } catch {
      DebugBuild.run {
        Log.debug("ECP", "query-textedit-state (snapshot) failed: \(error.localizedDescription)")
      }
      return nil
    }
  }

  // MARK: - Public snapshots (UI helpers)

  /// Perform an immediate ECP-2 snapshot of the device's active app + media state.
  /// Intended for UI to converge quickly (e.g. after connect or after we initiate a launch).
  func snapshotActiveStateNow(for device: DeviceInfo) async {
    await installTextEditSnapshotFetcherIfNeeded()
    await queryAndSetActiveAppECP2(for: device)
    await queryAndSetMediaState(for: device, logRaw: false)
    await queryAndSetAudioDeviceGlobalState(for: device)
  }

  // MARK: - Silo router public API

  /// Send a RemoteAction through the per-silo router.
  /// - Silo ordering is preserved (FIFO per siloId).
  /// - Only `.home` is wake-gated; other actions cancel any pending wake wait.
  func sendActionInSilo(
    _ action: RemoteAction,
    siloId: String,
    requiredDevices: [DeviceInfo],
    targetDevice: DeviceInfo
  ) async -> KeypressResult {
    if reconnectingIPs.contains(targetDevice.ipAddress) { return .reconnecting }

    // If a wake is already in-flight for this silo, a new gated request should extend the timeout.
    if action == .home {
      extendWakeDeadlineIfNeeded(siloId: siloId, waitTimeout: 5.0)
    }

    // If something is currently wake-gated and waiting, a new non-gated action should
    // cancel the wait so the queued operations can proceed in user-perceived order.
    if action != .home {
      cancelWakeWaitIfNeeded(siloId: siloId)
    }

    return await enqueueSilo(siloId) { [weak self] in
      guard let self else { return .failed }

      if action == .home {
        _ = await self.ensureAwakeIfNeeded(
          siloId: siloId,
          requiredDevices: requiredDevices,
          forceRefreshAfter: 2.0,
          waitTimeout: 5.0
        )
      }

      return await self.sendActionWithResult(action, to: targetDevice)
    }
  }

  /// Send a raw ECP key name through the per-silo router.
  /// Use this for non-`RemoteAction` keys such as:
  /// - `Backspace`
  /// - `Enter`
  /// - `Lit_a` / `Lit_%20` (typed characters)
  func sendKeypressInSilo(
    _ key: String,
    siloId: String,
    requiredDevices: [DeviceInfo],
    targetDevice: DeviceInfo
  ) async -> KeypressResult {
    if reconnectingIPs.contains(targetDevice.ipAddress) { return .reconnecting }

    // Keep ordering consistent with other button presses.
    cancelWakeWaitIfNeeded(siloId: siloId)

    return await enqueueSilo(siloId) { [weak self] in
      guard let self else { return .failed }
      let _ = requiredDevices  // Reserved for future wake gating if needed.
      return await self.sendKeypressWithResult(key, to: targetDevice)
    }
  }

  /// Query the currently active text edit state (if any) via ECP-2.
  func queryTexteditState(for device: DeviceInfo) async -> TexteditState? {
    await installTextEditSnapshotFetcherIfNeeded()
    guard await ensureConnected(to: device, primeState: false),
          let client = webSocketClients[device.ipAddress],
          await client.isConnected
    else { return nil }

    do {
      guard let data = try await client.queryTexteditState(),
            let xml = String(data: data, encoding: .utf8)
      else { return nil }
      let parsed = Self.parseTexteditState(xml: xml)
      if let parsed, parsed.texteditId.isEmpty || parsed.texteditId == "none" {
        await MainActor.run { RokuTextEditStateManager.shared.noteRemoteUpdate(nil, for: device.id) }
        return nil
      }
      if let parsed {
        await MainActor.run {
          RokuTextEditStateManager.shared.noteRemoteUpdate(
            RokuTextEditState(texteditId: parsed.texteditId, text: parsed.text),
            for: device.id
          )
        }
      }
      return parsed
    } catch {
      DebugBuild.run { Log.debug("ECP", "query-textedit-state failed: \(error.localizedDescription)") }
      return nil
    }
  }

  /// Set the full text for the active text edit field via ECP-2.
  func setTexteditText(texteditId: String, text: String, for device: DeviceInfo) async -> Bool {
    if texteditId.isEmpty || texteditId == "none" { return false }
    guard await ensureConnected(to: device, primeState: false),
          let client = webSocketClients[device.ipAddress],
          await client.isConnected
    else { return false }

    do {
      try await client.setTexteditText(texteditId: texteditId, text: text)
      return true
    } catch {
      DebugBuild.run { Log.debug("ECP", "set-textedit-text failed: \(error.localizedDescription)") }
      return false
    }
  }

  private static func parseTexteditState(xml: String) -> TexteditState? {
    // Best-effort XML scraping (Roku returns a small XML blob).
    // We intentionally keep this loose to tolerate firmware differences.
    func firstMatch(_ pattern: String) -> String? {
      guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return nil
      }
      let ns = xml as NSString
      guard let m = r.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)),
            m.numberOfRanges >= 2
      else { return nil }
      return ns.substring(with: m.range(at: 1))
    }

    // Common forms observed/expected:
    // - <textedit id="XYZ">...</textedit>
    // - <textedit-state textedit-id="XYZ">...</textedit-state>
    // - {"textedit-state":{"textedit-id":"XYZ"}}   (observed on some firmware)
    let id =
      firstMatch(#"<textedit\b[^>]*\bid="([^"]+)""#)
      ?? firstMatch(#"textedit-id="([^"]+)""#)
      ?? firstMatch(#"param-textedit-id":"([^"]+)""#)
      ?? firstMatch(#""textedit-id"\s*:\s*"([^"]+)""#)

    guard let texteditId = id, !texteditId.isEmpty else { return nil }

    let text =
      firstMatch(#"<text\b[^>]*>([^<]*)</text>"#)
      ?? firstMatch(#"<value\b[^>]*>([^<]*)</value>"#)
      ?? firstMatch(#""text"\s*:\s*"([^"]*)""#)
      ?? ""

    return TexteditState(texteditId: texteditId, text: text)
  }

  /// Launch an app through the per-silo router.
  /// - Silo ordering is preserved (FIFO per siloId).
  /// - App launches are wake-gated.
  func launchAppInSilo(
    appId: String,
    siloId: String,
    requiredDevices: [DeviceInfo],
    targetDevice: DeviceInfo
  ) async -> Bool {
    if reconnectingIPs.contains(targetDevice.ipAddress) { return false }

    // If a wake is already in-flight for this silo, a new gated request should extend the timeout.
    extendWakeDeadlineIfNeeded(siloId: siloId, waitTimeout: 5.0)

    return await enqueueSilo(siloId) { [weak self] in
      guard let self else { return false }
      _ = await self.ensureAwakeIfNeeded(
        siloId: siloId,
        requiredDevices: requiredDevices,
        forceRefreshAfter: 2.0,
        waitTimeout: 5.0
      )
      // IMPORTANT: Use ECP-2 WebSocket launch. HTTP /launch is frequently blocked (403).
      guard await self.ensureConnected(to: targetDevice, primeState: false) else { return false }
      let ok = await self.launchApp(appId: appId, device: targetDevice)

      // If we initiated a launch locally, don't wait for a media notification (Netflix may not send one)
      // and don't wait for the next 5s poll tick. Do a quick post-launch state sync.
      if ok {
        // Immediately bump MRU locally so the AppStrip reorders without waiting for polling.
        await MainActor.run {
          AppCacheManager.shared.noteAppActivated(appId: appId, deviceId: targetDevice.id)
        }

        Task { [weak self] in
          guard let self else { return }
          // Give Roku a moment to settle before snapshotting.
          try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
          await self.queryAndSetActiveAppECP2(for: targetDevice)
          await self.queryAndSetMediaState(for: targetDevice, logRaw: false)
        }
      }

      return ok
    }
  }

  // MARK: - Silo queueing

  private func enqueueSilo<T>(
    _ siloId: String,
    operation: @escaping @Sendable () async -> T
  ) async -> T {
    let prev = siloTails[siloId]

    let opTask = Task { [prev] in
      if let prev {
        _ = await prev.value
      }
      return await operation()
    }

    // Keep the tail as a Void task so subsequent ops can await ordering.
    siloTails[siloId] = Task { _ = await opTask.value }

    return await opTask.value
  }

  // MARK: - Wake gating

  private func cancelWakeWaitIfNeeded(siloId: String) {
    guard var ws = wakeStates[siloId] else { return }
    ws.cancelWait = true
    wakeStates[siloId] = ws
  }

  private func extendWakeDeadlineIfNeeded(siloId: String, waitTimeout: TimeInterval) {
    guard var ws = wakeStates[siloId] else { return }
    ws.deadline = max(ws.deadline, Date().addingTimeInterval(waitTimeout))
    wakeStates[siloId] = ws
  }

  private func ensureAwakeIfNeeded(
    siloId: String,
    requiredDevices: [DeviceInfo],
    forceRefreshAfter: TimeInterval,
    waitTimeout: TimeInterval
  ) async -> Bool {
    let now = Date()
    let requiredIds = Set(requiredDevices.map(\.id))

    // Start or extend single-flight wake task.
    if var existing = wakeStates[siloId] {
      // If the required set changed, treat it as a new wake attempt.
      if existing.requiredDeviceIds != requiredIds {
        wakeStates[siloId] = nil
        wakeTasks[siloId]?.cancel()
        wakeTasks[siloId] = nil
      } else {
        existing.deadline = max(existing.deadline, now.addingTimeInterval(waitTimeout))
        wakeStates[siloId] = existing
        if let task = wakeTasks[siloId] {
          return await task.value
        }
      }
    }

    wakeStates[siloId] = WakeState(
      startedAt: now,
      deadline: now.addingTimeInterval(waitTimeout),
      refreshSent: false,
      cancelWait: false,
      requiredDeviceIds: requiredIds
    )

    // Kick power-on to any devices that appear off.
    await sendPowerOnIfNeeded(for: requiredDevices)

    let task = Task { [weak self] in
      guard let self else { return false }
      return await self.wakeWaitLoop(
        siloId: siloId,
        requiredDevices: requiredDevices,
        forceRefreshAfter: forceRefreshAfter
      )
    }
    wakeTasks[siloId] = task
    let ok = await task.value
    wakeTasks[siloId] = nil
    wakeStates[siloId] = nil
    return ok
  }

  private func wakeWaitLoop(
    siloId: String,
    requiredDevices: [DeviceInfo],
    forceRefreshAfter: TimeInterval
  ) async -> Bool {
    while !Task.isCancelled {
      guard let ws = wakeStates[siloId] else { return false }

      if ws.cancelWait { return false }

      let now = Date()
      if now >= ws.deadline { return false }

      if await allRequiredDevicesOn(requiredDevices) {
        return true
      }

      let elapsed = now.timeIntervalSince(ws.startedAt)
      if !ws.refreshSent, elapsed >= forceRefreshAfter {
        var updated = ws
        updated.refreshSent = true
        wakeStates[siloId] = updated

        // Force a refresh in case notifications didn't come in.
        for device in requiredDevices {
          await queryPowerState(for: device)
        }
      }

      do {
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
      } catch {
        return false
      }
    }
    return false
  }

  private func allRequiredDevicesOn(_ devices: [DeviceInfo]) async -> Bool {
    await MainActor.run {
      let manager = DeviceStateManager.shared
      return devices.allSatisfy { device in
        let pm = manager.state(for: device.id).powerMode
        return Self.isConsideredOnForWake(device: device, powerMode: pm)
      }
    }
  }

  private nonisolated static func isConsideredOnForWake(device: DeviceInfo, powerMode: PowerMode)
    -> Bool
  {
    if device.isTV {
      // TVs: ready/displayOff are user-visible "off-ish", so require true on.
      return powerMode.isOn
    }
    // Streamers: `ready` is commonly reported even when the device is fully usable.
    // Treat anything other than explicit `off` as "on enough" for wake gating.
    return powerMode != .off
  }

  private func sendPowerOnIfNeeded(for devices: [DeviceInfo]) async {
    let offDevices: [DeviceInfo] = await MainActor.run {
      let manager = DeviceStateManager.shared
      return devices.filter { device in
        let pm = manager.state(for: device.id).powerMode
        if device.isTV {
          return !pm.isOn
        }
        // Streamers: only send PowerOn if we're confidently "off".
        return pm == .off
      }
    }
    guard !offDevices.isEmpty else { return }

    await withTaskGroup(of: Void.self) { group in
      for device in offDevices {
        group.addTask { [weak self] in
          guard let self else { return }
          _ = await self.sendKeypressWithResult("PowerOn", to: device)
        }
      }
    }
  }

  // MARK: - Media Progress Enablement

  /// Enable/disable artificial media position ticking for a set of device IDs.
  /// Intended for UI to limit ticking to the currently active device(s).
  func setMediaProgressEnabledDeviceIds(_ deviceIds: Set<String>) async {
    mediaProgressEnabledDeviceIds = deviceIds

    // Stop tickers for any device no longer enabled.
    for deviceId in Set(mediaProgressTasks.keys).subtracting(deviceIds) {
      stopMediaProgressTicker(for: deviceId)
    }
    for deviceId in Set(mediaResyncTasks.keys).subtracting(deviceIds) {
      stopMediaProgressTicker(for: deviceId)
    }

    // Start tickers for enabled devices if they're currently playing.
    for deviceId in deviceIds {
      await updateMediaProgressTicker(for: deviceId)
    }
  }

  // MARK: - Active State Polling
    // NOTE:
    // Some Roku apps (notably Netflix) often do NOT emit `media-player-state-changed`.
    // If we only update active app via media notifications, UI+MRU can get stuck (e.g. "still Hulu").
    // So we do a cheap ECP-2 poll on the *selected* device.

    private var activeStatePollEnabledDeviceIds: Set<String> = []
    private var activeStatePollTasks: [String: Task<Void, Never>] = [:]

    /// Enable/disable active-state polling for a set of device IDs.
    /// Intended to be used for the single "active" device displayed in the UI.
    func setActiveStatePollingEnabledDeviceIds(_ deviceIds: Set<String>) async {
      activeStatePollEnabledDeviceIds = deviceIds

      for deviceId in Set(activeStatePollTasks.keys).subtracting(deviceIds) {
        activeStatePollTasks[deviceId]?.cancel()
        activeStatePollTasks[deviceId] = nil
      }

      for deviceId in deviceIds {
        startActiveStatePollLoopIfNeeded(for: deviceId)
      }
    }

    private func startActiveStatePollLoopIfNeeded(for deviceId: String) {
      guard activeStatePollTasks[deviceId] == nil else { return }
      activeStatePollTasks[deviceId] = Task { [deviceId] in
        await self.activeStatePollLoop(for: deviceId)
      }
    }

    private func activeStatePollLoop(for deviceId: String) async {
    defer { activeStatePollTasks[deviceId] = nil }

      while !Task.isCancelled {
        if Task.isCancelled { break }
        if !activeStatePollEnabledDeviceIds.contains(deviceId) { break }

        if let device = devicesById[deviceId],
        let client = webSocketClients[device.ipAddress],
          await client.isConnected
        {
          // Poll active app reliably; poll media state to keep Now Playing accurate.
          await queryAndSetActiveAppECP2(for: device)
        await queryAndSetMediaState(for: device, logRaw: false)
        }

        // Sleep at the end so we do an immediate snapshot on enable/selection.
        do {
          try await Task.sleep(nanoseconds: 5_000_000_000)  // 5s
        } catch {
          break
        }
      }
    }

  // MARK: - App List Refresh Enablement

  /// Enable/disable app list refreshing for a set of device IDs.
  /// This is intended to be used for the currently active device so we can preserve MRU ordering
  /// without polling every device.
  func setAppListRefreshEnabledDeviceIds(_ deviceIds: Set<String>) async {
    appListRefreshEnabledDeviceIds = deviceIds

    // Stop refresh loops for any device no longer enabled.
    for deviceId in Set(appListRefreshTasks.keys).subtracting(deviceIds) {
      appListRefreshTasks[deviceId]?.cancel()
      appListRefreshTasks[deviceId] = nil
    }

    // Start refresh loops for enabled devices (if not already running).
    for deviceId in deviceIds {
      startAppListRefreshLoopIfNeeded(for: deviceId)
      await refreshAppsIfNeeded(for: deviceId, force: false, reason: "enable")
    }
  }

  private func startAppListRefreshLoopIfNeeded(for deviceId: String) {
    guard appListRefreshTasks[deviceId] == nil else { return }

    appListRefreshTasks[deviceId] = Task { [deviceId] in
      await self.appListRefreshLoop(for: deviceId)
    }
  }

  private func appListRefreshLoop(for deviceId: String) async {
    defer { appListRefreshTasks[deviceId] = nil }

    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)  // 5 minutes
      } catch {
        break
      }

      if Task.isCancelled { break }
      if !appListRefreshEnabledDeviceIds.contains(deviceId) { break }

      await refreshAppsIfNeeded(for: deviceId, force: false, reason: "hourly")
    }
  }

  private func refreshAppsIfNeeded(for deviceId: String, force: Bool, reason: String) async {
    guard appListRefreshEnabledDeviceIds.contains(deviceId) else { return }
    guard let device = devicesById[deviceId] else { return }

    let cache = await MainActor.run { AppCacheManager.shared }
    let maxAge: TimeInterval = 60 * 60  // 1 hour
    let isStale = await MainActor.run { cache.appsAreStale(for: deviceId, maxAge: maxAge) }
    if !force && !isStale { return }

    Log.debug("AppCache", "🔄 Refreshing app list for \(device.name) (\(reason))")
    await cache.fetchApps(for: deviceId, deviceName: device.name)
  }

  func noteActiveAppChanged(deviceId: String) async {
    // App changed: refresh MRU ordering immediately (only for active device).
    await refreshAppsIfNeeded(for: deviceId, force: true, reason: "app-changed")
  }

  // MARK: - Device Connection

  /// Unconditionally tear down the WebSocket connection for a device IP.
  /// Cancels any in-flight connect task, disconnects the client, and removes it from the pool.
  /// Callers should follow up with `ensureConnected` to establish a fresh connection.
  func tearDownConnection(for ip: String) async {
    connectTasksByIP[ip]?.cancel()
    connectTasksByIP[ip] = nil

    if let client = webSocketClients.removeValue(forKey: ip) {
      await client.disconnect()
    }
  }

  /// Atomically marks an IP as reconnecting and tears down the existing connection.
  /// Key sends are gated while the IP is in this set (see `sendActionInSilo`).
  func tearDownAndBeginReconnect(for ip: String) async {
    reconnectingIPs.insert(ip)
    connectTasksByIP[ip]?.cancel()
    connectTasksByIP[ip] = nil

    if let client = webSocketClients.removeValue(forKey: ip) {
      await client.disconnect()
    }
  }

  /// Clears the reconnecting flag so key sends resume for this IP.
  func clearReconnecting(for ip: String) {
    reconnectingIPs.remove(ip)
  }

  /// Check if a device is reachable (based on WebSocket connection state)
  func isDeviceReachable(_ deviceIP: String) async -> Bool {
    if let client = webSocketClients[deviceIP] {
      return await client.isConnected
    }
    return false
  }

  /// Ensure WebSocket is connected (for persistent connection/event monitoring)
  func ensureConnected(to device: DeviceInfo, primeState: Bool = false) async -> Bool {
    await installTextEditSnapshotFetcherIfNeeded()
    devicesById[device.id] = device

    // Always ensure notifications are routed with the current device ID.
    let deviceId = device.id
    if let existing = webSocketClients[device.ipAddress] {
      await existing.setNotificationHandler { notification in
        Task { @MainActor in
          Self.handleNotification(notification, for: deviceId)
        }
      }
    }

    let ok = await ensureConnectedSingleFlight(to: device)
    guard ok else { return false }

    if primeState {
      // Prime state on demand (e.g. when the user switches the active device).
      await queryAndSetPowerMode(for: device)
      await queryAndSetActiveApp(for: device)
      await queryAndSetMediaState(for: device)
      await queryAndSetAudioDeviceGlobalState(for: device)
    }

    return true
  }

  private func ensureConnectedSingleFlight(to device: DeviceInfo) async -> Bool {
    let ip = device.ipAddress

    if let existing = webSocketClients[ip], await existing.isConnected {
      return true
    }

    if let task = connectTasksByIP[ip] {
      return await task.value
    }

    let task = Task<Bool, Never> { [device] in
      let ip = device.ipAddress
      let deviceId = device.id

      await self.installTextEditSnapshotFetcherIfNeeded()

      // Re-check in case another caller connected first.
      if let existing = self.webSocketClients[ip], await existing.isConnected {
        return true
      }

      let client: RokuWebSocketClient
      if let existing = self.webSocketClients[ip] {
        client = existing
      } else {
        let newClient = RokuWebSocketClient(
          deviceIP: ip,
          deviceName: device.name,
          onNotification: { notification in
            Task { @MainActor in
              Self.handleNotification(notification, for: deviceId)
            }
          }
        )
        self.webSocketClients[ip] = newClient
        client = newClient
      }

      do  {
        try await client.connect()
        // Prime initial state from ECP-2.
        await self.queryAndSetPowerMode(for: device)
        await self.queryAndSetActiveApp(for: device)
        await self.queryAndSetMediaState(for: device)
        await self.queryAndSetAudioDeviceGlobalState(for: device)
        return true
      } catch {
        Log.warn(
          "ECP", "📵 Failed to connect to \(device.name) \(ip): \(error.localizedDescription)")
        self.webSocketClients.removeValue(forKey: ip)
        self.stopMediaProgressTicker(for: device.id)
        await MainActor.run { DeviceStateManager.shared.setPowerMode(.off, for: deviceId) }
        return false
      }
    }

    connectTasksByIP[ip] = task
    let ok = await task.value
    connectTasksByIP[ip] = nil
    return ok
  }

  // MARK: - Audio Device (ECP-2 query-audio-device)

  /// Query and apply the device's global volume/mute state.
  /// This is the only reliable way to get initial volume without waiting for a `volume-changed` event.
  private func queryAndSetAudioDeviceGlobalState(for device: DeviceInfo) async {
    let deviceId = device.id
    devicesById[deviceId] = device

    guard let client = webSocketClients[device.ipAddress], await client.isConnected else { return }

    do {
      guard let data = try await client.queryAudioDevice() else { return }
      let audio = try RokuAudioDeviceParser.parse(data)

      guard let volume = audio.global.volume, let muted = audio.global.muted else { return }
      await MainActor.run {
        DeviceStateManager.shared.setVolume(volume, muted: muted, for: deviceId)
      }
    } catch {
      DebugBuild.run {
        Log.debug("ECP", "query-audio-device failed for \(device.name): \(error.localizedDescription)")
      }
    }
  }

  /// Handle a WebSocket notification and update device state
  @MainActor
  private static func handleNotification(_ notification: RokuNotification, for deviceId: String) {
    let manager = DeviceStateManager.shared
    var state = manager.state(for: deviceId)
    let old = state
    var shouldNoisyLog = false

    switch notification {
    case .powerModeChanged(let mode):
      if let pm = PowerMode(rawValue: mode) {
        state.powerMode = pm
      }
      shouldNoisyLog = true
    case .volumeChanged(let vol, let isMuted):
      state.volume = vol
      state.muted = isMuted
    case .mediaPlayerStateChanged(let mediaState, let appId, let position, let duration, _):
      // Update active app from channel-id in media-player-state-changed
      // This is how Roku signals app changes (not via active-app-changed)
      if let appId = appId, !appId.isEmpty {
        let oldApp = state.activeApp
        if oldApp != appId {
          Log.info("ECP", "📱 Active app changed via media-player-state for device \(deviceId): \(oldApp ?? "nil") → \(appId)")
          state.activeApp = appId
          // Clear previous app's media state so we don't briefly display stale progress.
          state.mediaState = .idle
          state.mediaPosition = nil
          state.mediaDuration = nil

          Task { await RokuECPClient.shared.noteActiveAppChanged(deviceId: deviceId) }
        }
      }

      if let ms = DeviceState.MediaState(rawValue: mediaState) {
        state.mediaState = ms
      }
      // Update position and duration from notification (if provided)
      if let pos = position {
        state.mediaPosition = pos
      }
      if let dur = duration {
        state.mediaDuration = dur
      }
      // When media player closes, query active app to catch apps that don't send media-player-state
      // (e.g., Netflix, which only sends active-app-changed or nothing)
      if mediaState == "close" {
        Task {
          if let device = RokuDiscoveryService.shared.discoveredDevices.first(where: {
            $0.id == deviceId
          }) {
            await RokuECPClient.shared.queryAndSetActiveApp(for: device)
          }
        }
      }
      shouldNoisyLog = true
    case .texteditOpened(let s), .texteditChanged(let s), .texteditStateChanged(let s):
      RokuTextEditStateManager.shared.noteRemoteUpdate(s, for: deviceId)
    case .texteditClosed:
      RokuTextEditStateManager.shared.noteRemoteUpdate(nil, for: deviceId)
    case .other(let type, let params):
      Log.info(
        "ECP", "🔍 Unhandled notification type '\(type)' for device \(deviceId), params: \(params)")
      return  // Don't update state for unknown notifications
    }

    manager.updateState(state, for: deviceId)
    if shouldNoisyLog, old != state {
      Log.noisy(
        "DeviceState",
        "📱 State updated for \(deviceId): app=\(state.activeApp ?? "nil"), media=\(state.mediaState.rawValue), power=\(state.powerMode.rawValue)"
      )
    }

    if case .mediaPlayerStateChanged = notification {
      Task { await RokuECPClient.shared.updateMediaProgressTicker(for: deviceId) }
    }
  }

  // MARK: - Power State Query

  /// Query power state for a single device (public)
  func queryPowerState(for device: DeviceInfo) async {
    await queryAndSetPowerMode(for: device)
  }

  /// Query power states for all discovered devices
  /// Call this after discovery to populate initial states
  func queryAllDevicePowerStates(_ devices: [DeviceInfo]) async {
    Log.info("ECP", "Querying power states for \(devices.count) device(s)...")
    await withTaskGroup(of: Void.self) { group in
      for device in devices {
        group.addTask {
          await self.queryAndSetPowerMode(for: device)
        }
      }
    }
    Log.info("ECP", "Power state queries complete")
  }

  /// Query and set active app for a device (ECP-2).
  private func queryAndSetActiveApp(for device: DeviceInfo) async {
    await queryAndSetActiveAppECP2(for: device)
  }

  // MARK: - Media Player Query (ECP-2)

  private struct MediaPlayerSnapshot: Sendable {
    let state: DeviceState.MediaState
    let position: Int?
    let duration: Int?
    let isLive: Bool?
    let isLiveBlocked: Bool?
  }

  private func queryAndSetMediaState(for device: DeviceInfo, logRaw: Bool = false) async {
    let deviceId = device.id
    devicesById[deviceId] = device

    guard let client = webSocketClients[device.ipAddress], await client.isConnected else { return }

    do {
      let data = try await client.queryMediaPlayer()

      if logRaw {
        if let data, let payload = String(data: data, encoding: .utf8) {
          Log.noisy("ECP", "📦 query-media-player raw for \(device.name): \(payload)")
        } else if let data {
          Log.noisy("ECP", "📦 query-media-player raw for \(device.name): <non-utf8 payload, \(data.count) bytes>")
        } else {
          Log.noisy("ECP", "📦 query-media-player raw for \(device.name): <nil payload>")
        }
      }

      guard let snapshot = parseMediaPlayerSnapshot(data) else {
        let preview = data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.prefix(240)) } ?? "nil"
        Log.debug("ECP", "Media query parse failed for \(device.name) (preview): \(preview)")
        return
      }

      Log.debug(
        "ECP",
        "Media query snapshot for \(device.name): state=\(snapshot.state.rawValue), pos=\(snapshot.position?.description ?? "nil"), dur=\(snapshot.duration?.description ?? "nil")"
      )

      await MainActor.run {
        let manager = DeviceStateManager.shared
        let old = manager.state(for: deviceId)
        var state = old

        state.mediaState = snapshot.state
        if let pos = snapshot.position {
          state.mediaPosition = pos
        }
        if let dur = snapshot.duration {
          state.mediaDuration = dur
        }
        state.isLive = snapshot.isLive
        state.isLiveBlocked = snapshot.isLiveBlocked

        if snapshot.state == .idle {
          state.mediaPosition = nil
          state.mediaDuration = nil
          state.isLive = nil
          state.isLiveBlocked = nil
        }

        if old != state {
          manager.updateState(state, for: deviceId)
          Log.noisy(
            "DeviceState",
            "📱 State updated for \(deviceId): app=\(state.activeApp ?? "nil"), media=\(state.mediaState.rawValue), power=\(state.powerMode.rawValue)"
          )
        }
      }
      await updateMediaProgressTicker(for: deviceId)
    } catch {
      Log.debug("ECP", "Media query failed for \(device.name): \(error.localizedDescription)")
    }
  }

  // MARK: - Active App Query (ECP-2)

  private func queryAndSetActiveAppECP2(for device: DeviceInfo) async {
    let deviceId = device.id
    devicesById[deviceId] = device

    guard let client = webSocketClients[device.ipAddress], await client.isConnected else { return }

    do {
      let data = try await client.queryActiveApp()
      let activeApp = data.map { parseApps($0).first } ?? nil
      let oldAppId = await MainActor.run {
        DeviceStateManager.shared.state(for: deviceId).activeApp
      }
      let newAppId = activeApp?.id

      if oldAppId != newAppId {
        let nameHint: String? = await MainActor.run {
          AppCacheManager.shared.apps(for: deviceId).first(where: { $0.id == (newAppId ?? "") })?
            .name
        }
        Log.info(
          "ECP",
          "📱 Active app (poll) for \(device.name): \(oldAppId ?? "nil") → \(newAppId ?? "nil")\(nameHint.map { " (\($0))" } ?? "")"
        )
      }

      await MainActor.run { DeviceStateManager.shared.setActiveApp(newAppId, for: deviceId) }
    } catch {
      Log.debug("ECP", "Active app query failed for \(device.name): \(error.localizedDescription)")
    }
  }

  // MARK: - Media Progress Ticking

  private func updateMediaProgressTicker(for deviceId: String) async {
    guard mediaProgressEnabledDeviceIds.contains(deviceId) else {
      stopMediaProgressTicker(for: deviceId)
      return
    }

    let state = await MainActor.run { DeviceStateManager.shared.state(for: deviceId) }
    if state.mediaState == .play {
      startMediaProgressTickerIfNeeded(for: deviceId)
    } else {
      stopMediaProgressTicker(for: deviceId)
    }
  }

  private func startMediaProgressTickerIfNeeded(for deviceId: String) {
    guard mediaProgressEnabledDeviceIds.contains(deviceId) else { return }
    guard mediaProgressTasks[deviceId] == nil else { return }

    let task = Task { [deviceId] in
      await self.mediaProgressLoop(for: deviceId)
    }
    mediaProgressTasks[deviceId] = task
  }

  private func stopMediaProgressTicker(for deviceId: String) {
    mediaProgressTasks[deviceId]?.cancel()
    mediaProgressTasks[deviceId] = nil

    mediaResyncTasks[deviceId]?.cancel()
    mediaResyncTasks[deviceId] = nil
  }

  private func mediaProgressLoop(for deviceId: String) async {
    defer { mediaProgressTasks[deviceId] = nil }

    var ticksSinceResync = 0

    while !Task.isCancelled {
      do {
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1s
      } catch {
        break
      }

      if Task.isCancelled { break }

      // Stop if ticker is no longer enabled.
      if !mediaProgressEnabledDeviceIds.contains(deviceId) { break }

      // Stop if not playing anymore.
      let state = await MainActor.run { DeviceStateManager.shared.state(for: deviceId) }
      guard state.mediaState == .play else { break }

      // Stop if connection dropped.
      guard
        let device = devicesById[deviceId],
        let client = webSocketClients[device.ipAddress],
        await client.isConnected
      else {
        break
      }

      // Increment position from the *latest* state so real updates always win.
      await MainActor.run {
        let manager = DeviceStateManager.shared
        var latest = manager.state(for: deviceId)
        guard latest.mediaState == .play else { return }

        if let pos = latest.mediaPosition {
          let next = pos + 1000
          if let dur = latest.mediaDuration, dur > 0 {
            latest.mediaPosition = min(next, dur)
          } else {
            latest.mediaPosition = next
          }
          manager.updateState(latest, for: deviceId)
        }
      }

      ticksSinceResync += 1
      if ticksSinceResync >= 5 {
        ticksSinceResync = 0
        // If active-state polling is enabled for this device, that loop already performs
        // a 5s media-player snapshot. Avoid double-polling.
        if !activeStatePollEnabledDeviceIds.contains(deviceId) {
          startMediaResyncIfNeeded(for: deviceId)
        }
      }
    }
  }

  private func startMediaResyncIfNeeded(for deviceId: String) {
    guard mediaProgressEnabledDeviceIds.contains(deviceId) else { return }
    if let existing = mediaResyncTasks[deviceId], !existing.isCancelled {
      return
    }

    mediaResyncTasks[deviceId] = Task { [deviceId] in
      await self.mediaResyncLoop(deviceId: deviceId)
    }
  }

  private func mediaResyncLoop(deviceId: String) async {
    defer { mediaResyncTasks[deviceId] = nil }
    guard let device = devicesById[deviceId] else { return }
    await queryAndSetMediaState(for: device)
  }

  private func parseMediaPlayerSnapshot(_ data: Data?) -> MediaPlayerSnapshot? {
    guard let data, let payload = String(data: data, encoding: .utf8) else { return nil }

    // Some devices return the HTTP /query/media-player XML, others may return JSON-like params.
    if payload.contains("<") {
      guard let playerTag = extractPlayerTag(from: payload) else {
        return nil
      }

      let rawState = extractXMLAttribute("state", fromTag: playerTag) ?? "none"
      let mappedState: DeviceState.MediaState
      switch rawState {
      case "play": mappedState = .play
      case "pause": mappedState = .pause
      case "stop": mappedState = .stop
      case "close": mappedState = .idle
      default: mappedState = .idle
      }

      // Some Roku firmware reports position/duration as attributes on <player>,
      // others use nested elements like <position>123 ms</position>.
      let position =
        extractXMLAttribute("position", fromTag: playerTag).flatMap(parseMillisecondsLike)
        ?? extractXMLElementText("position", from: payload).flatMap(parseMillisecondsLike)
      let duration =
        extractXMLAttribute("duration", fromTag: playerTag).flatMap(parseMillisecondsLike)
        ?? extractXMLElementText("duration", from: payload).flatMap(parseMillisecondsLike)

      let isLive = extractXMLElementText("is_live", from: payload).flatMap(parseBoolLike)
      let isLiveTag = extractStartTag("is_live", from: payload)
      let isLiveBlocked = isLiveTag.flatMap { extractXMLAttribute("blocked", fromTag: $0) }.flatMap(parseBoolLike)

      return MediaPlayerSnapshot(
        state: mappedState,
        position: position,
        duration: duration,
        isLive: isLive,
        isLiveBlocked: isLiveBlocked
      )
    }

    // JSON-ish fallback (matches the notification keys).
    if payload.contains("param-media-player-state") {
      let rawState = extractJSONStringValue("param-media-player-state", from: payload) ?? "none"
      let mappedState: DeviceState.MediaState
      switch rawState {
      case "play": mappedState = .play
      case "pause": mappedState = .pause
      case "stop": mappedState = .stop
      case "close": mappedState = .idle
      default: mappedState = .idle
      }

      let position = extractJSONStringValue("param-media-player-position", from: payload).flatMap(parseMillisecondsLike)
      let duration = extractJSONStringValue("param-media-player-duration", from: payload).flatMap(parseMillisecondsLike)

      return MediaPlayerSnapshot(
        state: mappedState,
        position: position,
        duration: duration,
        isLive: nil,
        isLiveBlocked: nil
      )
    }

    return nil
  }

  private func extractPlayerTag(from xml: String) -> String? {
    // Match "<player ...>" or "<player .../>" (single-line).
    let pattern = #"<player\b[^>]*>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(xml.startIndex..., in: xml)
    guard let match = regex.firstMatch(in: xml, options: [], range: range),
          let tagRange = Range(match.range(at: 0), in: xml) else { return nil }
    return String(xml[tagRange])
  }

  private func extractStartTag(_ name: String, from xml: String) -> String? {
    // Match "<name ...>" or "<name>" and return the start tag.
    let pattern = #"<\#(name)\b[^>]*>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(xml.startIndex..., in: xml)
    guard let match = regex.firstMatch(in: xml, options: [], range: range),
          let tagRange = Range(match.range(at: 0), in: xml) else { return nil }
    return String(xml[tagRange])
  }

  private func extractXMLAttribute(_ name: String, fromTag tag: String) -> String? {
    let pattern = #"\b\#(name)\s*=\s*"([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(tag.startIndex..., in: tag)
    guard let match = regex.firstMatch(in: tag, options: [], range: range),
          match.numberOfRanges >= 2,
          let valueRange = Range(match.range(at: 1), in: tag) else { return nil }
    return String(tag[valueRange])
  }

  private func extractXMLElementText(_ name: String, from xml: String) -> String? {
    // Match: <name>text</name> and return the trimmed inner text.
    let pattern = #"<\#(name)\b[^>]*>([^<]*)</\#(name)>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(xml.startIndex..., in: xml)
    guard let match = regex.firstMatch(in: xml, options: [], range: range),
          match.numberOfRanges >= 2,
          let valueRange = Range(match.range(at: 1), in: xml) else { return nil }
    return String(xml[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func extractJSONStringValue(_ key: String, from payload: String) -> String? {
    // Matches: "key":"value"
    let pattern = #""\#(key)"\s*:\s*"([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }
    let range = NSRange(payload.startIndex..., in: payload)
    guard let match = regex.firstMatch(in: payload, options: [], range: range),
          match.numberOfRanges >= 2,
          let valueRange = Range(match.range(at: 1), in: payload) else { return nil }
    return String(payload[valueRange])
  }

  private func parseMillisecondsLike(_ value: String) -> Int? {
    // Accept "123", "123 ms", "123ms", etc.
    let digits = value.filter(\.isNumber)
    return Int(digits)
  }

  private func parseBoolLike(_ value: String) -> Bool? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "1", "yes": return true
    case "false", "0", "no": return false
    default: return nil
    }
  }

  /// Query device-info (ECP-2) and set the current power mode
  private func queryAndSetPowerMode(for device: DeviceInfo) async {
    let deviceId = device.id

    // Ensure we have a WebSocket connection; if it fails, treat device as unreachable/off.
    guard await ensureConnected(to: device, primeState: false),
      let client = webSocketClients[device.ipAddress]
    else {
      await MainActor.run { DeviceStateManager.shared.setPowerMode(.off, for: deviceId) }
      return
    }

    do {
      let data = try await client.queryDeviceInfo()
      guard let data else {
        await MainActor.run { DeviceStateManager.shared.setPowerMode(.off, for: deviceId) }
        return
      }

      let fields = parseAllXMLFields(data)
      let mode = PowerMode.fromECPPowerMode(fields["power-mode"])
      await MainActor.run { DeviceStateManager.shared.setPowerMode(mode, for: deviceId) }
    } catch {
      await MainActor.run { DeviceStateManager.shared.setPowerMode(.off, for: deviceId) }
    }
  }

  // MARK: - Keypress Commands

  /// Result of a keypress attempt
  enum KeypressResult {
    case success
    case failed
    case limitedMode  // HTTP returned 403, device needs "Permissive" mode
    case unreachable  // Device is off or not on network
    case reconnecting // Key discarded -- WebSocket is being re-established
  }

  /// Send a keypress to a Roku device
  /// Tries WebSocket (ecp-2) first, falls back to HTTP ECP
  func sendKeypress(_ key: String, to device: DeviceInfo) async -> Bool {
    let result = await sendKeypressWithResult(key, to: device)
    return result == .success
  }

  /// Send a keypress and get detailed result (for UI feedback)
  func sendKeypressWithResult(_ key: String, to device: DeviceInfo) async -> KeypressResult {
    let trace = DebugBuild.isEnabled ? String(UUID().uuidString.prefix(8)) : ""
    DebugBuild.run {
      Log.debug(
        "ECP",
        "[\(trace)] keypress start key=\(key) device=\(device.name) id=\(device.id) ip=\(device.ipAddress)"
      )
    }

    // MARK: - Power / wake special-case (WoL fallback)

    let isPowerishKey = (key == "PowerOn" || key == "Power")
    if isPowerishKey {
      // If we're confidently "red" (true off), send WoL immediately and don't attempt to connect.
      // We can't know whether the device is unplugged; treat WoL as best-effort.
      let pm: PowerMode = await MainActor.run {
        DeviceStateManager.shared.state(for: device.id).powerMode
      }

      if pm == .off, device.canAttemptWakeOnLAN {
        DebugBuild.run {
          Log.info(
            "WoL",
            "[\(trace)] sending WoL first (powerMode=off) for \(device.name) macs=\(device.wakeOnLANMacAddresses)"
          )
        }
        _ = await WakeOnLAN.wake(macAddresses: device.wakeOnLANMacAddresses, repeats: 2)
        // Treat as success: we initiated the user's intent to turn the device on.
        return .success
      }
    }

    // Try WebSocket (ecp-2) first - this is the authenticated, robust approach
    let wsResult = await sendKeypressViaWebSocket(key, to: device, trace: trace)
    if wsResult.success {
      DebugBuild.run { Log.debug("ECP", "[\(trace)] keypress done via WebSocket: success") }
      return .success
    }

    // If WebSocket indicated unreachable (connection failed), device is likely off.
    if wsResult.unreachable {
      // If this looks like a "turn on" intent, fall back to WoL when supported.
      if isPowerishKey, device.canAttemptWakeOnLAN {
        DebugBuild.run {
          Log.info(
            "WoL",
            "[\(trace)] WS unreachable; falling back to WoL for \(device.name) macs=\(device.wakeOnLANMacAddresses)"
          )
        }
        _ = await WakeOnLAN.wake(macAddresses: device.wakeOnLANMacAddresses, repeats: 2)
        return .success
      }

      DebugBuild.run { Log.debug("ECP", "[\(trace)] keypress failed: unreachable") }
      return .unreachable
    }

    // WebSocket connected but send failed.
    DebugBuild.run { Log.debug("ECP", "[\(trace)] keypress failed via WebSocket") }
    return .failed
  }

  /// HTTP result type
  private enum HTTPResult {
    case success
    case forbidden  // 403 - device in limited mode
    case unreachable  // Network error - device off or not on network
    case failed
  }

  #if ROCKYOU_ENABLE_ECP1_FALLBACK
    /// ⚠️ HTTP fallback (ECP-1). Do not use unless explicitly enabled for recovery.
    private func sendKeypressViaHTTP(_ key: String, to device: DeviceInfo, trace: String) async
      -> HTTPResult
    {
      guard let baseURL = device.ecpBaseURL,
        let url = URL(string: "/keypress/\(key)", relativeTo: baseURL)
      else {
        Log.error("ECP", "Invalid URL for keypress \(key) to \(device.name)")
        return .failed
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.timeoutInterval = 2.0

      do {
        DebugBuild.run { Log.debug("ECP", "[\(trace)] HTTP keypress POST \(url.absoluteString)") }
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
          if http.statusCode == 403 {
            Log.warn(
              "ECP", "HTTP 403 Forbidden for \(key) to \(device.name) - device in Limited mode")
            return .forbidden
          }
          if (200...299).contains(http.statusCode) {
            return .success
          }
          Log.error("ECP", "HTTP \(http.statusCode) for \(key) to \(device.name)")
          return .failed
        }
        return .failed
      } catch let error as URLError {
        // Distinguish network-level failures (device off, unreachable)
        switch error.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
          .notConnectedToInternet:
          DebugBuild.run {
            Log.debug(
              "ECP", "[\(trace)] 📵 HTTP unreachable: \(device.name) - \(error.localizedDescription)"
            )
          }
          return .unreachable
        default:
          Log.error("ECP", "HTTP error for \(key) to \(device.name): \(error.localizedDescription)")
          return .failed
        }
      } catch {
        Log.error("ECP", "HTTP error for \(key) to \(device.name): \(error.localizedDescription)")
        return .failed
      }
    }
  #else
    @available(*, unavailable, message: "HTTP ECP-1 is disabled. Use ECP-2 WebSocket only.")
    private func sendKeypressViaHTTP(_ key: String, to device: DeviceInfo, trace: String) async -> HTTPResult { .failed }
  #endif

  /// Send keypress via WebSocket (ecp-2 protocol)
  /// Returns: (success, wasUnreachable)
  private func sendKeypressViaWebSocket(_ key: String, to device: DeviceInfo, trace: String) async
    -> (success: Bool, unreachable: Bool)
  {
    let deviceIP = device.ipAddress
    let deviceId = device.id

    // IMPORTANT: Never create a second client here. Always reuse the shared pool + single-flight connect.
    let ok = await ensureConnected(to: device, primeState: false)
    guard ok, let client = webSocketClients[deviceIP], await client.isConnected else {
      await MainActor.run { DeviceStateManager.shared.setPowerMode(.off, for: deviceId) }
      return (success: false, unreachable: true)
    }

    // Send keypress via WebSocket
    do {
      DebugBuild.run { Log.debug("ECP", "[\(trace)] WS send key=\(key) ip=\(deviceIP)") }
      try await client.sendKeypress(key)
      DebugBuild.run { Log.debug("ECP", "[\(trace)] WS send ok key=\(key) ip=\(deviceIP)") }
      return (success: true, unreachable: false)
    } catch {
      // Connection may have dropped - remove client so we reconnect next time
      Log.warn("ECP", "WebSocket send failed \(key) to \(device.name) \(deviceIP): \(error.localizedDescription)")
      webSocketClients.removeValue(forKey: deviceIP)
      return (success: false, unreachable: false)
    }
  }

  /// Disconnect WebSocket for a device
  func disconnectWebSocket(for deviceIP: String) async {
    if let client = webSocketClients.removeValue(forKey: deviceIP) {
      await client.disconnect()
    }
  }

  /// Send a RemoteAction to a Roku device
  func sendAction(_ action: RemoteAction, to device: DeviceInfo) async -> Bool {
    await sendKeypress(action.ecpKey, to: device)
  }

  /// Send a RemoteAction and get detailed result
  func sendActionWithResult(_ action: RemoteAction, to device: DeviceInfo) async -> KeypressResult {
    await sendKeypressWithResult(action.ecpKey, to: device)
  }

  #if ROCKYOU_ENABLE_ECP1_FALLBACK
    /// ⚠️ HTTP fallback (ECP-1). Do not use unless explicitly enabled for recovery.
    func launchApp(_ appId: String, on device: DeviceInfo) async -> Bool {
      guard let baseURL = device.ecpBaseURL,
        let url = URL(string: "/launch/\(appId)", relativeTo: baseURL)
      else {
        return false
      }

      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.timeoutInterval = 5.0

      do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
          return (200...299).contains(http.statusCode)
        }
        return false
      } catch {
        return false
      }
    }
  #else
    @available(
      *, unavailable,
      message: "HTTP ECP-1 is disabled. Use ECP-2 WebSocket launchApp(appId:device:) instead."
    )
    func launchApp(_ appId: String, on device: DeviceInfo) async -> Bool { false }
  #endif

  // MARK: - Device Properties API

  #if ROCKYOU_ENABLE_ECP1_FALLBACK
    /// Fetch all available properties from a Roku device (HTTP ECP-1; fallback only).
    func fetchProperties(for device: DeviceInfo) async -> RokuDeviceProperties? {
      guard let baseURL = device.ecpBaseURL else {
        return nil
      }

      // Fetch all endpoints concurrently
      async let deviceInfoTask = fetchDeviceInfo(baseURL: baseURL)
      async let appsTask = fetchApps(baseURL: baseURL)
      async let activeAppTask = fetchActiveApp(baseURL: baseURL)

      let deviceInfo = await deviceInfoTask
      let apps = await appsTask
      let activeApp = await activeAppTask

      guard !deviceInfo.isEmpty else {
        return nil
      }

      let properties = RokuDeviceProperties(
        deviceId: device.id,
        fetchedAt: Date(),
        deviceInfo: deviceInfo,
        installedApps: apps,
        activeApp: activeApp,
        mediaPlayerState: nil  // Media state comes via WebSocket notifications only
      )

      // Cache it
      propertiesCache[device.id] = properties
      return properties
    }
  #else
    @available(*, unavailable, message: "HTTP ECP-1 is disabled. This helper is only for emergency recovery."
    )
    func fetchProperties(for device: DeviceInfo) async -> RokuDeviceProperties? { nil }
  #endif

  /// Get cached properties (if available)
  func getCachedProperties(for deviceId: String) -> RokuDeviceProperties? {
    propertiesCache[deviceId]
  }

  /// Fetch parsed `/query/device-info` fields via ECP-2 (WebSocket).
  /// This is the preferred way to access device-info; HTTP ECP-1 is intentionally disabled by default.
  func fetchDeviceInfoFieldsECP2(for device: DeviceInfo) async -> [String: String]? {
    guard await ensureConnected(to: device, primeState: false),
          let client = webSocketClients[device.ipAddress]
    else { return nil }

    do {
      guard let data = try await client.queryDeviceInfo() else { return nil }
      return parseAllXMLFields(data)
    } catch {
      return nil
    }
  }

  /// Clear cache for a device
  func clearCache(for deviceId: String) {
    propertiesCache.removeValue(forKey: deviceId)
  }

  // MARK: - App Management

  // MARK: - ECP-2 Commands (WebSocket - Preferred)

  /// Fetch installed apps for a device (via WebSocket ECP-2)
  func fetchApps(for device: DeviceInfo) async -> [RokuApp] {
    // Ensure we have a WebSocket connection
    guard await ensureConnected(to: device) else {
      Log.warn("ECP", "Cannot fetch apps - not connected to \(device.name)")
      return []
    }

    guard let client = webSocketClients[device.ipAddress] else { return [] }

    do {
      guard let data = try await client.queryApps() else {
        Log.debug("ECP", "No app data returned for \(device.name)")
        return []
      }

      let apps = parseApps(data)
      Log.debug("ECP", "Fetched \(apps.count) apps via WebSocket for \(device.name)")
      return apps
    } catch {
      Log.error("ECP", "Error fetching apps: \(error.localizedDescription)")
      return []
    }
  }

  // MARK: - Debug Utilities

  /// 🔧 DEBUG: Dump all apps from all discovered devices to console
  /// Call this from RokuDiscoveryService after discovery completes.
  /// Comment out when not needed - generates a lot of log output!
  static func dumpAllAppsFromAllDevices() {
    Task {
      let discovery = await MainActor.run { RokuDiscoveryService.shared }
      let devices = await MainActor.run { discovery.discoveredDevices }

      Log.debug("ECP", "═══════════════════════════════════════════════════════════════")
      Log.debug("ECP", "🔧 APP ID DUMP - \(devices.count) device(s)")
      Log.debug("ECP", "═══════════════════════════════════════════════════════════════")

      for device in devices {
        Log.debug("ECP", "")
        Log.debug("ECP", "📺 Device: \(device.name) (\(device.ipAddress))")
        Log.debug("ECP", "───────────────────────────────────────────────────────────────")

        let apps = await RokuECPClient.shared.fetchApps(for: device)

        if apps.isEmpty {
          Log.debug("ECP", "   (no apps or connection failed)")
        } else {
          // Sort by name for easier reading
          let sorted = apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
          for app in sorted {
            // Format: "  12345  Netflix" - ID left-padded for alignment
            let paddedId = app.id.padding(toLength: 8, withPad: " ", startingAt: 0)
            Log.debug("ECP", "   \(paddedId)  \(app.name)")
          }
          Log.debug("ECP", "")
          Log.debug("ECP", "   Total: \(apps.count) apps")
        }
      }

      Log.debug("ECP", "")
      Log.debug("ECP", "═══════════════════════════════════════════════════════════════")
      Log.debug("ECP", "🔧 END APP ID DUMP")
      Log.debug("ECP", "═══════════════════════════════════════════════════════════════")
    }
  }

  /// Fetch app icon (via WebSocket ECP-2)
  func fetchAppIcon(appId: String, device: DeviceInfo) async -> Data? {
    guard let client = webSocketClients[device.ipAddress] else { return nil }

    do {
      return try await client.queryAppIcon(appId: appId)
    } catch {
      return nil
    }
  }

  /// Launch an app on the device (via WebSocket ECP-2)
  func launchApp(appId: String, device: DeviceInfo) async -> Bool {
    guard let client = webSocketClients[device.ipAddress] else { return false }

    do {
      try await client.launchApp(appId: appId)
      return true
    } catch {
      Log.error("ECP", "Error launching app \(appId): \(error.localizedDescription)")
      return false
    }
  }

  // ╔══════════════════════════════════════════════════════════════════════════╗
  // ║                                                                          ║
  // ║  ⚠️⚠️⚠️  WARNING: HTTP ECP-1 FALLBACK ZONE - DO NOT USE DIRECTLY  ⚠️⚠️⚠️  ║
  // ║                                                                          ║
  // ║  The methods below use HTTP (ECP-1) which is BLOCKED by many Roku       ║
  // ║  devices in "Limited Mode" (returns 403 Forbidden).                     ║
  // ║                                                                          ║
  // ║  ALWAYS use the WebSocket ECP-2 methods above instead:                  ║
  // ║    • fetchApps(for:)      → Use RokuWebSocketClient.queryApps()         ║
  // ║    • fetchAppIcon()       → Use RokuWebSocketClient.queryAppIcon()      ║
  // ║    • launchApp()          → Use RokuWebSocketClient.launchApp()         ║
  // ║    • sendKeypress()       → Use RokuWebSocketClient.sendKeypress()      ║
  // ║                                                                          ║
  // ║  These HTTP methods are ONLY kept for:                                  ║
  // ║    1. Initial device discovery (before WebSocket is established)        ║
  // ║    2. Fallback if WebSocket fails (very rare)                           ║
  // ║                                                                          ║
  // ╚══════════════════════════════════════════════════════════════════════════╝

  // MARK: - HTTP ECP-1 Endpoints (Fallback Only - Prefer WebSocket)

  #if ROCKYOU_ENABLE_ECP1_FALLBACK
    /// GET /query/device-info - All device metadata
    /// Note: This HTTP endpoint usually works even in Limited Mode
    private func fetchDeviceInfo(baseURL: URL) async -> [String: String] {
      guard let url = URL(string: "/query/device-info", relativeTo: baseURL) else { return [:] }
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [:] }
        return parseAllXMLFields(data)
      } catch {
        return [:]
      }
    }

    /// GET /query/apps - Installed channels/apps
    private func fetchApps(baseURL: URL) async -> [RokuApp] {
      guard let url = URL(string: "/query/apps", relativeTo: baseURL) else {
        Log.error("ECP", "Failed to construct /query/apps URL from \(baseURL)")
        return []
      }
      Log.debug("ECP", "Fetching apps from: \(url.absoluteString)")
      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
          Log.error("ECP", "No HTTP response")
          return []
        }
        Log.debug("ECP", "Apps response: \(http.statusCode), \(data.count) bytes")
        guard http.statusCode == 200 else {
          Log.error("ECP", "Apps request failed with status: \(http.statusCode)")
          return []
        }
        let apps = parseApps(data)
        Log.debug("ECP", "Parsed \(apps.count) apps")
        return apps
      } catch {
        Log.error("ECP", "Apps fetch error: \(error.localizedDescription)")
        return []
      }
    }

    /// GET /query/active-app - Currently running app
    private func fetchActiveApp(baseURL: URL) async -> RokuApp? {
      guard let url = URL(string: "/query/active-app", relativeTo: baseURL) else { return nil }
      do {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return parseApps(data).first
      } catch {
        return nil
      }
    }
  #else
    @available(*, unavailable, message: "HTTP ECP-1 is disabled. Use ECP-2 WebSocket only.")
    private func fetchDeviceInfo(baseURL: URL) async -> [String: String] { [:] }

    @available(*, unavailable, message: "HTTP ECP-1 is disabled. Use ECP-2 WebSocket only.")
    private func fetchApps(baseURL: URL) async -> [RokuApp] { [] }

    @available(*, unavailable, message: "HTTP ECP-1 is disabled. Use ECP-2 WebSocket only.")
    private func fetchActiveApp(baseURL: URL) async -> RokuApp? { nil }
  #endif

  // MARK: - XML Parsing Helpers

  /// Parse ALL XML elements (not just a predefined list)
  private func parseAllXMLFields(_ data: Data) -> [String: String] {
    (try? RokuXMLFieldParser.parseAllFields(data)) ?? [:]
  }

  /// Parse <app> elements from /query/apps or /query/active-app
  private func parseApps(_ data: Data) -> [RokuApp] {
    guard let xml = String(data: data, encoding: .utf8) else { return [] }
    var apps: [RokuApp] = []

    // Pattern: <app id="12345" type="appl" version="1.0">App Name</app>
    let pattern = #"<app\s+id="([^"]+)"(?:\s+type="([^"]*)")?(?:\s+version="([^"]*)")?[^>]*>([^<]+)</app>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return apps }

    let range = NSRange(xml.startIndex..., in: xml)
    let matches = regex.matches(in: xml, options: [], range: range)

    for match in matches {
      guard let idRange = Range(match.range(at: 1), in: xml),
            let nameRange = Range(match.range(at: 4), in: xml) else { continue }

      let id = String(xml[idRange])
      let name = String(xml[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)

      var type: String? = nil
      var version: String? = nil

      if match.range(at: 2).location != NSNotFound,
         let typeRange = Range(match.range(at: 2), in: xml) {
        type = String(xml[typeRange])
      }
      if match.range(at: 3).location != NSNotFound,
         let versionRange = Range(match.range(at: 3), in: xml) {
        version = String(xml[versionRange])
      }

      apps.append(RokuApp(id: id, name: name, type: type, version: version))
    }

    return apps
  }

  /// Parse attributes from <player> element in media-player response
  private func parsePlayerAttributes(_ xml: String) -> [String: String] {
    var result: [String: String] = [:]

    // Find <player ...> element and extract attributes
    let pattern = #"<player\s+([^>]+)>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
          let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
          let attrRange = Range(match.range(at: 1), in: xml) else { return result }

    let attrs = String(xml[attrRange])

    // Parse individual attributes
    let attrPattern = #"([a-zA-Z_-]+)="([^"]*)""#
    guard let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) else { return result }

    let attrMatches = attrRegex.matches(in: attrs, options: [], range: NSRange(attrs.startIndex..., in: attrs))
    for m in attrMatches {
      if let keyRange = Range(m.range(at: 1), in: attrs),
         let valueRange = Range(m.range(at: 2), in: attrs) {
        result["player-\(attrs[keyRange])"] = String(attrs[valueRange])
      }
    }

    return result
  }
}
