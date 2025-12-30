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
import WidgetKit

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

  /// Watch-owned: last active device on watch (used by complication/widget targeting).
  private(set) var lastActiveDeviceId: String? {
    get { WatchSurfaceSnapshotStore.lastActiveDeviceId }
    set {
      WatchSurfaceSnapshotStore.lastActiveDeviceId = newValue
    }
  }

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

    sendToPhone(.keypress(deviceId: deviceId, deviceIdx: selectedDeviceIdx, key: action.ecpKey))
  }

  /// Request device list from iPhone
  func requestDevices() {
    DispatchQueue.main.async { self.isScanning = true }
    sendToPhone(.requestDevices) { [weak self] reply in
      self?.handleHandshakeReply(reply)
    }
  }

  /// Handshake - called on startup when phone becomes reachable
  func performHandshake() {
    DispatchQueue.main.async { self.isScanning = true }
    sendToPhone(.handshake) { [weak self] reply in
      guard let self else { return }
      self.handleHandshakeReply(reply)
    }

    // Retry after 2 seconds if we still don't have devices
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
      if self?.devices.isEmpty == true && self?.isPhoneReachable == true {
        self?.sendToPhone(.handshake) { [weak self] reply in
          self?.handleHandshakeReply(reply)
        }
      }
    }
  }

  /// Select a device by its stable ID (serial number)
  func selectDevice(id: String) {
    selectedDeviceId = id
    lastActiveDeviceId = id

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
    sendToPhone(.requestApps(deviceId: deviceId)) { reply in
      if case .error(let msg) = reply {
        Log.error("Watch", "requestApps error: \(msg)")
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
    sendToPhone(.launchApp(deviceId: deviceId, deviceIdx: selectedDeviceIdx, appId: appId))
  }

  /// Request an app icon from iPhone
  @MainActor
  func requestIcon(appId: String) {
    guard let deviceId = selectedDeviceId else { return }
    let hash = AppCacheManager.shared.iconHash(for: appId, deviceId: deviceId)
    sendToPhone(.requestIcon(WCIconRequest(deviceId: deviceId, appId: appId, hash: hash)))
  }

  /// Request all icons for current device, sending current hashes (in display order)
  @MainActor
  func requestIconsWithHashes(appIds: [String]) {
    guard let deviceId = selectedDeviceId else { return }
    let ordered = appIds.map { appId in
      WCIconHash(appId: appId, hash: AppCacheManager.shared.iconHash(for: appId, deviceId: deviceId))
    }
    Log.debug("Watch", "📤 Requesting icons with hashes for \(appIds.count) apps (ordered)")
    sendToPhone(.requestIconsBatch(WCIconsBatchRequest(deviceId: deviceId, ordered: ordered)))
  }

  // MARK: - Message Sending

  private func sendToPhone(_ request: WCRequest, replyHandler: ((WCReply) -> Void)? = nil) {
    guard let session = session else {
      Log.warn("Watch", "No session")
      return
    }
    guard session.isReachable else {
      Log.debug("Watch", "Phone not reachable, dropping message")
      return
    }

    do {
      let payload = try WCWireCodec.encode(.request(request))
      Log.debug("Watch", "📤 Sending: \(String(describing: request))")

      if let handler = replyHandler {
        session.sendMessageData(payload, replyHandler: { data in
          do {
            let msg = try WCWireCodec.decode(data)
            guard case .reply(let reply) = msg else {
              handler(.error("unexpected reply"))
              return
            }
            handler(reply)
          } catch {
            handler(.error("decode failed"))
          }
        }) { error in
          Log.error("Watch", "Send error: \(error.localizedDescription)")
        }
      } else {
        session.sendMessageData(payload, replyHandler: nil) { error in
          Log.error("Watch", "Send error: \(error.localizedDescription)")
        }
      }
    } catch {
      Log.error("Watch", "Failed to encode WC request: \(error.localizedDescription)")
    }
  }

  // MARK: - Response Handling
  private func handleHandshakeReply(_ reply: WCReply) {
    guard case .handshake(let payload) = reply else { return }
    applyDevices(payload.devices)
    Task { @MainActor in
      WatchAppSettings.shared.applySyncedSettings(payload.settings)
    }
  }

  private func applyDevices(_ devices: [DeviceInfo]) {
    DispatchQueue.main.async {
      self.isScanning = false
      self.devices = devices

      if self.selectedDeviceId == nil {
        if let last = self.lastActiveDeviceId, devices.contains(where: { $0.id == last }) {
          self.selectedDeviceId = last
        } else if let firstTV = self.tvs.first {
          self.selectedDeviceId = firstTV.id
        } else if let first = devices.first {
          self.selectedDeviceId = first.id
        }
      }

      self.saveCache()
    }
  }

  private func handleDeviceListEvent(_ event: WCDeviceListEvent) {
    applyDevices(event.devices)
    if let settings = event.settings {
      Task { @MainActor in
        WatchAppSettings.shared.applySyncedSettings(settings)
      }
    }
  }

  private func handleAppListEvent(_ event: WCAppListEvent) {
    let deviceId = event.deviceId
    let apps = event.apps
    let mruDict = event.mru

    Log.debug("Watch", "📱 Received \(apps.count) apps for device: \(deviceId)")

    guard deviceId == selectedDeviceId else {
      Log.warn(
        "Watch",
        "handleAppList: deviceId mismatch (got \(deviceId), selected \(selectedDeviceId ?? "nil"))"
      )
      return
    }

    DispatchQueue.main.async {
      self.appRequestRetryTask?.cancel()
      self.apps = apps
      AppCacheManager.shared.setApps(apps, for: deviceId)

      let mruMap: [String: Date] = mruDict.mapValues { Date(timeIntervalSince1970: $0) }
      AppCacheManager.shared.setMRU(mruMap, for: deviceId)

      self.requestIconsWithHashes(appIds: apps.map(\.id))
    }
  }

  private func handleMRUUpdate(deviceId: String, mru: [String: TimeInterval]) {
    guard deviceId == selectedDeviceId else { return }
    Log.debug("Watch", "📊 Received MRU update for device: \(deviceId) (\(mru.count) apps)")
    DispatchQueue.main.async {
      let mruMap: [String: Date] = mru.mapValues { Date(timeIntervalSince1970: $0) }
      AppCacheManager.shared.setMRU(mruMap, for: deviceId)
    }
  }

  private func handleDeviceStateEvent(deviceId: String, state: DeviceState) {
    DispatchQueue.main.async {
      DeviceStateManager.shared.updateState(state, for: deviceId)
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

  // Receive binary data from iPhone (typed messages + icons)
  func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    if WCWireCodec.isLikelyJSONMessage(messageData),
       let msg = try? WCWireCodec.decode(messageData),
       case .event(let event) = msg {
      switch event {
      case .deviceList(let evt):
        handleDeviceListEvent(evt)
      case .appList(let evt):
        handleAppListEvent(evt)
      case .deviceState(let deviceId, let state):
        handleDeviceStateEvent(deviceId: deviceId, state: state)
      case .mruUpdate(let deviceId, let mru):
        handleMRUUpdate(deviceId: deviceId, mru: mru)
      }
      return
    }

    handleIconData(messageData)
  }

  // Receive applicationContext (persistent device list)
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    handleApplicationContext(applicationContext)
  }

  private func handleApplicationContext(_ context: [String: Any]) {
    guard
      let data = context[WCApplicationContext.key] as? Data,
      let decoded = try? JSONDecoder().decode(WCApplicationContext.self, from: data)
    else { return }

    let snapshot = decoded.snapshot

    DispatchQueue.main.async {
      self.devices = snapshot.devices

      for (deviceId, state) in snapshot.deviceStates {
        DeviceStateManager.shared.updateState(state, for: deviceId)
      }

      WatchSurfaceSnapshotStore.saveSnapshot(snapshot)

      if self.selectedDeviceId == nil {
        if let last = self.lastActiveDeviceId, snapshot.devices.contains(where: { $0.id == last }) {
          self.selectedDeviceId = last
        } else if let first = snapshot.devices.first {
          self.selectedDeviceId = first.id
        }
      }

      self.saveCache()
      WidgetCenter.shared.reloadAllTimelines()
    }

    Task { @MainActor in
      WatchAppSettings.shared.applySyncedSettings(decoded.settings)
    }
  }
}
