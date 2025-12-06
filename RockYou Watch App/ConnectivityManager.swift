//
//  ConnectivityManager.swift
//  RockYou Watch App
//
//  Message-passing proxy to iPhone for Roku control.
//
//  Architecture:
//  - Watch sends commands to iPhone via sendMessage
//  - iPhone forwards to Roku and sends responses/notifications back
//  - Device list synced via applicationContext (persistent)
//

import Foundation
import Combine
import CoreGraphics

import WatchConnectivity

// MARK: - Connectivity Manager

@MainActor
final class ConnectivityManager: NSObject, ObservableObject, DeviceStateProviding {
  static let shared = ConnectivityManager()

  // MARK: - Published State

  @Published private(set) var isPhoneReachable: Bool = false
  @Published private(set) var isScanning: Bool = false  // Waiting for device list from iPhone
  @Published private(set) var devices: [DeviceInfo] = []
  @Published private(set) var selectedDeviceId: String?  // Stable device ID (serial)
  @Published private(set) var apps: [RokuApp] = []  // Apps for selected device (cached by AppCacheManager)

  // MARK: - Computed

  var selectedDevice: DeviceInfo? {
    guard let id = selectedDeviceId else { return nil }
    return devices.first { $0.id == id }
  }

  /// The idx for messaging (derived from selectedDeviceId)
  var selectedDeviceIdx: String? {
    selectedDevice?.idx
  }

  var tvs: [DeviceInfo] { devices.filter { $0.isTV } }

  var hardwareControlsAvailable: Bool {
    selectedDevice?.isTV == true
  }

  // MARK: - DeviceStateProviding

  @MainActor
  func powerMode(for deviceId: String) -> PowerMode {
    DeviceStateManager.shared.state(for: deviceId).powerMode
  }

  @MainActor
  func deviceState(for deviceId: String) -> DeviceState {
    DeviceStateManager.shared.state(for: deviceId)
  }

  // MARK: - Private

  private var session: WCSession?

  // MARK: - Init

  private override init() {
    super.init()
    if WCSession.isSupported() {
      session = WCSession.default
      session?.delegate = self
      session?.activate()
    }
    loadCached()
  }

  private func loadCached() {
    selectedDeviceId = UserDefaults.standard.string(forKey: "selectedDeviceId")

    // Load cached devices
    if let data = UserDefaults.standard.data(forKey: "cachedDevices"),
       let cached = try? JSONDecoder().decode([DeviceInfo].self, from: data) {
      DispatchQueue.main.async { self.devices = cached }
    }

    // Load cached apps from AppCacheManager (single source of truth)
    if let deviceId = selectedDeviceId {
      let cachedApps = AppCacheManager.shared.apps(for: deviceId)
      if !cachedApps.isEmpty {
        Log.info("Watch", "📦 Loaded \(cachedApps.count) cached apps for device \(deviceId)")
        DispatchQueue.main.async { self.apps = cachedApps }
      }
    }
  }

  private func saveCache() {
    if let id = selectedDeviceId {
      UserDefaults.standard.set(id, forKey: "selectedDeviceId")
    }
    if let data = try? JSONEncoder().encode(devices) {
      UserDefaults.standard.set(data, forKey: "cachedDevices")
    }
    // Apps are cached by AppCacheManager
  }

  // MARK: - Public API

  /// Send a remote action to the selected device
  func send(action: RemoteAction) {
    guard let deviceId = selectedDeviceId else { return }

    // Hardware controls require a TV pairing (for now).
    // StreamBar support can extend this once we have a richer capability model.
    let isHardwareControl =
      action == .volumeUp || action == .volumeDown
      || action == .volumeMute || action == .power
    if isHardwareControl, !hardwareControlsAvailable {
      Log.debug("Watch", "Hardware control unavailable for streamer selection (action=\(action))")
      return
    }

    var message: [String: Any] = ["type": "keypress", "deviceId": deviceId, "key": action.ecpKey]
    if let idx = selectedDeviceIdx {
      // Backward-compatible with older iPhone builds
      message["device"] = idx
    }
    sendToPhone(message)
  }

  /// Request device list from iPhone
  func requestDevices() {
    DispatchQueue.main.async { self.isScanning = true }
    sendToPhone(["type": "requestDevices"])
  }

  /// Handshake - called on startup when phone becomes reachable
  func performHandshake() {
    DispatchQueue.main.async { self.isScanning = true }
    sendToPhone(["type": "handshake"]) { [weak self] response in
      self?.handleDeviceList(response)
    }

    // Retry after 2 seconds if we still don't have devices
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      if self?.devices.isEmpty == true && self?.isPhoneReachable == true {
        self?.sendToPhone(["type": "handshake"]) { [weak self] response in
          self?.handleDeviceList(response)
        }
      }
    }
  }

  /// Select a device by its stable ID (serial number)
  func selectDevice(id: String) {
    selectedDeviceId = id

    // Load cached apps immediately while waiting for fresh ones
    let cachedApps = AppCacheManager.shared.apps(for: id)
    if !cachedApps.isEmpty {
      Log.debug("Watch", "📦 Using \(cachedApps.count) cached apps for device \(id)")
      apps = cachedApps
    } else {
      apps = []  // Clear apps when switching to device with no cache
    }

    saveCache()
    requestApps()  // Request fresh apps from phone
  }

  /// Track pending app request for retry
  private var appRequestRetryTask: Task<Void, Never>?

  /// Request apps for the selected device (with retry on timeout)
  func requestApps() {
    guard let deviceId = selectedDeviceId else {
      Log.warn("Watch", "requestApps: no selected device")
      return
    }

    // Cancel any pending retry
    appRequestRetryTask?.cancel()

    Log.debug("Watch", "📲 Requesting apps for device: \(deviceId)")
    sendToPhone(["type": "requestApps", "deviceId": deviceId]) { [weak self] response in
      // Reply received - cancel retry
      self?.appRequestRetryTask?.cancel()

      if let apps = response["apps"] as? [[String: Any]] {
        Log.debug("Watch", "✅ Got \(apps.count) apps in reply")
        Task { @MainActor in
          self?.handleAppList(response)
        }
      } else if let error = response["error"] as? String {
        Log.error("Watch", "requestApps error: \(error)")
      }
    }

    // Retry after 5 seconds if no response
    appRequestRetryTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 seconds
      guard !Task.isCancelled else { return }

      await MainActor.run {
        guard self?.apps.isEmpty == true else { return }  // Only retry if still empty
        Log.debug("Watch", "🔄 Retrying requestApps (no response)")
        self?.requestApps()
      }
    }
  }

  /// Launch an app on the selected device
  func launchApp(_ appId: String) {
    guard let deviceId = selectedDeviceId else { return }
    let idx = selectedDeviceIdx ?? "?"
    Log.noisy("Watch", "launchApp appId=\(appId) deviceId=\(deviceId) deviceIdx=\(idx)")
    var message: [String: Any] = ["type": "launchApp", "deviceId": deviceId, "appId": appId]
    if let idx = selectedDeviceIdx {
      // Backward-compatible with older iPhone builds
      message["device"] = idx
    }
    sendToPhone(message)
  }

  /// Request an app icon from iPhone
  @MainActor
  func requestIcon(appId: String) {
    guard let deviceId = selectedDeviceId else { return }
    let hash = AppCacheManager.shared.iconHash(for: appId, deviceId: deviceId)
    sendToPhone(["type": "requestIcon", "deviceId": deviceId, "appId": appId, "hash": hash])
  }

  /// Request all icons for current device, sending current hashes (in display order)
  @MainActor
  func requestIconsWithHashes(appIds: [String]) {
    guard let deviceId = selectedDeviceId else { return }
    // Preserve order by sending array of [appId, hash] pairs
    let orderedHashes = appIds.map { appId in
      [appId, AppCacheManager.shared.iconHash(for: appId, deviceId: deviceId)]
    }
    Log.debug("Watch", "📤 Requesting icons with hashes for \(appIds.count) apps (ordered)")
    sendToPhone(["type": "requestIconsBatch", "deviceId": deviceId, "orderedHashes": orderedHashes])
  }

  // MARK: - Message Sending

  private func sendToPhone(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
    guard let session = session else {
      Log.warn("Watch", "No session")
      return
    }
    guard session.isReachable else {
      Log.debug("Watch", "Phone not reachable, dropping message")
      return
    }

    let msgType = message["type"] as? String ?? "?"
    Log.debug("Watch", "📤 Sending: \(msgType)")

    if let handler = replyHandler {
      session.sendMessage(message, replyHandler: handler) { error in
        Log.error("Watch", "Send error: \(error.localizedDescription)")
      }
    } else {
      session.sendMessage(message, replyHandler: nil) { error in
        Log.error("Watch", "Send error: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Response Handling

  private func handleDeviceList(_ data: [String: Any]) {
    guard let deviceDicts = data["devices"] as? [[String: Any]] else {
      DispatchQueue.main.async { self.isScanning = false }
      return
    }

    let newDevices: [DeviceInfo] = deviceDicts.compactMap { dict in
      guard let idx = dict["idx"] as? String,
            let id = dict["id"] as? String,
            let name = dict["name"] as? String,
            let ip = dict["ip"] as? String,
            let deviceType = dict["deviceType"] as? String
      else { return nil }
      let location = dict["location"] as? String
      let isTV = (deviceType == "tv")
      return DeviceInfo(
        id: id,
        name: name,
        location: location,
        ipAddress: ip,
        isTV: isTV,
        idx: idx
      )
    }

    DispatchQueue.main.async {
      self.isScanning = false
      self.devices = newDevices
      // Auto-select first TV if present; otherwise first device.
      if self.selectedDeviceId == nil {
        if let firstTV = self.tvs.first {
          self.selectedDeviceId = firstTV.id
        } else if let first = self.devices.first {
          self.selectedDeviceId = first.id
        }
      }
      self.saveCache()
    }

    if let settings = data["settings"] as? [String: Any] {
      Task { @MainActor in
        WatchAppSettings.shared.applySyncedSettings(settings)
      }
    }
  }

  private func handleAppList(_ data: [String: Any]) {
    guard let appDicts = data["apps"] as? [[String: Any]],
          let deviceId = data["deviceId"] as? String else {
      Log.warn("Watch", "handleAppList: missing apps or deviceId in data")
      return
    }

    Log.debug("Watch", "📱 Received \(appDicts.count) apps for device: \(deviceId)")

    // Only update if this is for our selected device
    guard deviceId == selectedDeviceId else {
      Log.warn("Watch", "handleAppList: deviceId mismatch (got \(deviceId), selected \(selectedDeviceId ?? "nil"))")
      return
    }

    let newApps: [RokuApp] = appDicts.compactMap { dict in
      guard let id = dict["id"] as? String,
            let name = dict["name"] as? String
      else { return nil }
      let type = dict["type"] as? String
      return RokuApp(id: id, name: name, type: type, version: nil, deviceId: deviceId)
    }

    Log.debug("Watch", "✅ Parsed \(newApps.count) apps")
    DispatchQueue.main.async {
      self.apps = newApps
      AppCacheManager.shared.setApps(newApps, for: deviceId)

      // Apply MRU if included (shared code - same structure)
      if let mruDict = data["mru"] as? [String: TimeInterval] {
        let mruMap: [String: Date] = mruDict.mapValues { Date(timeIntervalSince1970: $0) }
        AppCacheManager.shared.setMRU(mruMap, for: deviceId)
        Log.debug("Watch", "✅ Applied MRU data for \(mruMap.count) apps")
      }

      // Trigger batch icon sync with hashes
      self.requestIconsWithHashes(appIds: newApps.map(\.id))
    }
  }

  /// Handle MRU update from iPhone (when CloudKit syncs MRU changes)
  private func handleMRUUpdate(_ data: [String: Any]) {
    guard let deviceId = data["deviceId"] as? String,
      let mruDict = data["mru"] as? [String: TimeInterval]
    else {
      Log.warn("Watch", "handleMRUUpdate: missing deviceId or mru in data")
      return
    }

    // Only update if this is for our selected device
    guard deviceId == selectedDeviceId else {
      return
    }

    Log.debug("Watch", "📊 Received MRU update for device: \(deviceId) (\(mruDict.count) apps)")

    DispatchQueue.main.async {
      // Convert TimeInterval dict to Date dict (shared code - same structure)
      let mruMap: [String: Date] = mruDict.mapValues { Date(timeIntervalSince1970: $0) }
      AppCacheManager.shared.setMRU(mruMap, for: deviceId)
      Log.debug("Watch", "✅ Applied MRU update - UI will re-sort automatically")
    }
  }

  /// Handle device state update from iPhone
  private func handleDeviceState(_ data: [String: Any]) {
    DispatchQueue.main.async {
      DeviceStateManager.shared.updateFromMessage(data)
    }
  }

  /// Handle binary icon data:
  /// "appId|deviceId|hash|" + imageBytes
  private func handleIconData(_ data: Data) {
    guard let headerEnd = findNthPipe(in: data, n: 3),
      let header = String(data: data.prefix(headerEnd), encoding: .utf8)
    else {
      Log.warn("Watch", "handleIconData: unexpected icon payload; purging icon cache and reloading")
      AppCacheManager.shared.clearAllIcons()
      if !apps.isEmpty { requestIconsWithHashes(appIds: apps.map(\.id)) }
      return
    }

    let parts = header.split(separator: "|", omittingEmptySubsequences: false)
    guard parts.count >= 3 else {
      Log.warn("Watch", "handleIconData: unexpected header parts; purging icon cache and reloading")
      AppCacheManager.shared.clearAllIcons()
      if !apps.isEmpty { requestIconsWithHashes(appIds: apps.map(\.id)) }
      return
    }

    let appId = String(parts[0])
    let deviceId = String(parts[1])
    let hash = String(parts[2])
    let iconData = data.suffix(from: headerEnd + 1)  // Skip trailing "|"

    Log.debug(
      "Watch",
      "📥 Received icon appId=\(appId), hash=\(hash.prefix(8))..., size=\(iconData.count) bytes"
    )

    // Save to shared cache with hash and notify proxy provider
    DispatchQueue.main.async {
      AppCacheManager.shared.saveIcon(
        appId: appId,
        deviceId: deviceId,
        data: Data(iconData),
        hash: hash
      )
      WatchProxyProvider.shared.didReceiveIcon(appId: appId, data: Data(iconData))
    }
  }

  /// Find position of nth "|" character in data
  private func findNthPipe(in data: Data, n: Int) -> Int? {
    let pipe = UInt8(ascii: "|")
    var pipeCount = 0
    for (index, byte) in data.enumerated() {
      if byte == pipe {
        pipeCount += 1
        if pipeCount == n {
          return index
        }
      }
    }
    return nil
  }
}

// MARK: - WCSessionDelegate

extension ConnectivityManager: WCSessionDelegate {

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    if let error = error {
      Log.error("Watch", "WCSession activation failed: \(error.localizedDescription)")
      return
    }

    let reachable = session.isReachable
    DispatchQueue.main.async {
      self.isPhoneReachable = reachable
    }

    // Check for cached applicationContext
    if !session.receivedApplicationContext.isEmpty {
      handleApplicationContext(session.receivedApplicationContext)
    }

    // If phone is already reachable, initiate handshake now
    // (sessionReachabilityDidChange won't fire if already reachable)
    if reachable {
      Log.info("Watch", "📱 Phone already reachable on activation, initiating handshake")
      performHandshake()
    }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    DispatchQueue.main.async {
      self.isPhoneReachable = reachable
    }

    if reachable {
      performHandshake()
    }
  }

  // Receive dictionary messages from iPhone
  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    guard let type = message["type"] as? String else { return }

    switch type {
    case "deviceList":
      handleDeviceList(message)
    case "appList":
      handleAppList(message)
    case "deviceState":
        handleDeviceState(message)
      case "mruUpdate":
        handleMRUUpdate(message)
    default:
      break
    }
  }

  // Receive binary data from iPhone (used for icons)
  func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    handleIconData(messageData)
  }

  // Receive applicationContext (persistent device list)
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    handleApplicationContext(applicationContext)
  }

  private func handleApplicationContext(_ context: [String: Any]) {
    if let devicesData = context["devices"] as? Data,
       let decoded = try? JSONDecoder().decode([DeviceInfo].self, from: devicesData) {
      DispatchQueue.main.async {
        self.devices = decoded
        if self.selectedDeviceId == nil, let first = self.tvs.first {
          self.selectedDeviceId = first.id
        }
        self.saveCache()
      }
    }

    if let settings = context["settings"] as? [String: Any] {
      Task { @MainActor in
        WatchAppSettings.shared.applySyncedSettings(settings)
      }
    }
  }
}
