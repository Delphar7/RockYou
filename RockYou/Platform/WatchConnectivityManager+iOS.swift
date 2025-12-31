//
//  WatchConnectivityManager.swift
//  RockYou
//
//  Message-passing bridge between Watch and Roku devices.
//
//  Architecture:
//  - Receives commands from Watch via sendMessage
//  - Forwards to Roku via ECP/WebSocket
//  - Sends responses and notifications back to Watch
//  - Syncs device list via applicationContext (persistent)
//

import Foundation
import Combine
import UIKit
import WatchConnectivity

// MARK: - Watch Connectivity Manager

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
  static let shared = WatchConnectivityManager()

  // MARK: - Published State

  @Published private(set) var isWatchReachable: Bool = false
  @Published private(set) var isPaired: Bool = false
  @Published private(set) var isWatchAppInstalled: Bool = false

  /// Non-nil when we detect a configuration problem (e.g., received message but Watch app not registered)
  @Published private(set) var configurationIssue: ConfigurationIssue?

  /// Describes a Watch/iPhone configuration problem
  enum ConfigurationIssue: Equatable {
    case watchAppNotEmbedded    // Received message but isWatchAppInstalled=false
    case notPaired              // No Watch paired with this iPhone

    var title: String {
      switch self {
      case .watchAppNotEmbedded: return "Watch App Not Registered"
      case .notPaired: return "No Watch Paired"
      }
    }

    var message: String {
      switch self {
      case .watchAppNotEmbedded:
        return "The Watch app is communicating but isn't properly registered. " +
               "This usually means the Watch app wasn't embedded in the iPhone app during build. " +
               "Try deleting both apps and reinstalling the iPhone app, then install the Watch app from the Watch app on your iPhone."
      case .notPaired:
        return "No Apple Watch is paired with this iPhone. Pair your Watch in the Watch app to use remote control from your wrist."
      }
    }
  }

  private var session: WCSession?

  /// Device index mapping (idx → device)
  private var deviceMap: [String: DeviceInfo] = [:]

  /// Debounce task for device list updates
  private var deviceUpdateTask: Task<Void, Never>?
    private var deviceStateObserverToken: UUID?

  /// Keypress throttling: minimum 200ms between keypresses to Roku
  private var lastKeypressTime: Date = .distantPast
  private let keypressThrottleInterval: TimeInterval = 0.2  // 200ms

  private override init() {
    super.init()
    guard WCSession.isSupported() else { return }
    let wcSession = WCSession.default
    session = wcSession
    wcSession.delegate = self
    wcSession.activate()

    // Subscribe to device discovery changes (debounced)
    RokuDiscoveryService.shared.onDevicesChanged = { [weak self] _ in
      Task { @MainActor in
        self?.scheduleDeviceListUpdate()
      }
    }

    // Subscribe to icon hash changes - proactively push to Watch
    Task { @MainActor in
      AppCacheManager.shared.onIconHashChanged = { [weak self] appId, deviceId, data, hash in
        Task { @MainActor in
          guard let self = self else { return }
          // Resize and push to Watch
          if let resized = self.resizeIconForWatch(data) {
            Log.debug("iPhone", "🔄 Proactively pushing updated icon: \(appId)")
            self.sendIconDataToWatch(appId: appId, deviceId: deviceId, data: resized, hash: hash)
          }
        }
      }

        // Subscribe to device state changes - push to Watch
        deviceStateObserverToken = DeviceStateManager.shared.addStateChangedHandler {
          [weak self] deviceId, state in
          self?.pushStateToWatch(deviceId: deviceId, state: state)
        }

        // Subscribe to CloudKit MRU updates - push to Watch
        CloudKitHouseholdStore.shared.onMRUUpdated = { [weak self] deviceId, mruMap in
          Task { @MainActor in
            guard let self = self else { return }
            // Convert Date dict to TimeInterval dict for transmission
            let mruDict: [String: TimeInterval] = mruMap.mapValues { $0.timeIntervalSince1970 }
            self.sendToWatch(.event(.mruUpdate(deviceId: deviceId, mru: mruDict)))
          }
        }
    }
  }

  /// Push device state to watch
  private func pushStateToWatch(deviceId: String, state: DeviceState) {
    sendToWatch(.event(.deviceState(deviceId: deviceId, state: state)))
    updateWatchApplicationContext()
  }

  /// Push all known device states to watch (called when watch becomes reachable)
  private func pushAllDeviceStates() {
    for device in RokuDiscoveryService.shared.discoveredDevices {
      let state = DeviceStateManager.shared.state(for: device.id)
      sendToWatch(.event(.deviceState(deviceId: device.id, state: state)))
    }
    updateWatchApplicationContext()
  }

  /// Debounced device list push - coalesces rapid updates
  private func scheduleDeviceListUpdate() {
    deviceUpdateTask?.cancel()
    deviceUpdateTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 sec debounce
      guard !Task.isCancelled else { return }
      pushDeviceListToWatch()
      updateWatchApplicationContext()
    }
  }

  /// Public entry point for settings changes: refresh the WC applicationContext and (if reachable)
  /// push a deviceList event so the watch can apply the new settings immediately.
  func refreshWatchContext() {
    updateWatchApplicationContext()
    pushDeviceListToWatch()
  }

  // MARK: - Message Handling

  private func handleWatchRequest(_ request: WCRequest) async -> WCReply {
    switch request {
    case .handshake, .requestDevices:
      let devices = await buildDeviceListWaitingForDiscovery()
      return .handshake(WCHandshakeReply(devices: devices, settings: AppSettings.shared.watchConnectivitySettings))

    case .keypress(let deviceId, let deviceIdx, let key):
      return await handleKeypress(deviceId: deviceId, deviceIdx: deviceIdx, key: key)

    case .requestApps(let deviceId):
      return await handleRequestApps(deviceId: deviceId)

    case .launchApp(let deviceId, let deviceIdx, let appId):
      return await handleLaunchApp(deviceId: deviceId, deviceIdx: deviceIdx, appId: appId)

    case .requestIcon(let req):
      return await handleRequestIcon(req)

    case .requestIconsBatch(let req):
      return await handleRequestIconsBatch(req)
    }
  }

  /// Wait for discovery to complete if it's running and we have no devices yet
  private func buildDeviceListWaitingForDiscovery() async -> [DeviceInfo] {
    let discovery = RokuDiscoveryService.shared

    // If empty and still scanning, wait up to 5 seconds
    if discovery.discoveredDevices.isEmpty && discovery.isScanning {
      for _ in 0..<50 {  // 50 x 100ms = 5 seconds max
        try? await Task.sleep(nanoseconds: 100_000_000)
        if !discovery.isScanning || !discovery.discoveredDevices.isEmpty {
          break
        }
      }
    }

    return buildDeviceList()
  }

  private func handleKeypress(deviceId: String?, deviceIdx: String?, key: String) async -> WCReply {
    let now = Date()
    Log.noisy(
      "iPhoneWC",
      "keypress: received key=\(key) deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil")")

    // Throttle: skip if less than 200ms since last keypress
    let elapsed = now.timeIntervalSince(lastKeypressTime)
    if elapsed < keypressThrottleInterval {
      Log.debug("iPhone", "⏭️ Keypress throttled: \(key) (only \(Int(elapsed * 1000))ms since last)")
      return .throttled
    }
    lastKeypressTime = now

    Log.debug(
      "iPhone",
      "📥 Keypress received: \(key) for deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil")"
    )

    let device: DeviceInfo? = {
      if let deviceId {
        return RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
      }
      if let deviceIdx {
        return deviceMap[deviceIdx] ?? lookupDevice(idx: deviceIdx)
      }
      return nil
    }()

    guard let device else {
      Log.noisy(
        "iPhoneWC",
        "keypress: unknown device deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil") key=\(key)"
      )
      Log.warn(
        "iPhone", "Unknown device: deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil")")
      return .error("unknown device")
    }

    // Send keypress via RokuECPClient (WebSocket first, HTTP fallback)
    let sendTime = Date()
    Log.noisy(
      "iPhoneWC",
      "keypress: forwarding to Roku key=\(key) deviceId=\(device.id) name='\(device.name)'")
    let success = await RokuECPClient.shared.sendKeypress(key, to: device)
    let sendElapsed = Date().timeIntervalSince(sendTime) * 1000
    Log.debug("iPhone", "📤 Keypress sent: \(key) → \(success ? "✅" : "❌") (\(Int(sendElapsed))ms)")
    Log.noisy(
      "iPhoneWC",
      "keypress: RokuECPClient result=\(success ? "ok" : "fail") key=\(key) deviceId=\(device.id)")
    return success ? .ok : .error("keypress failed")
  }

  private func buildDeviceList() -> [DeviceInfo] {
    let devices = RokuDiscoveryService.shared.discoveredDevices
    deviceMap.removeAll()

    return devices.enumerated().map { index, device in
      let idx = String(index + 1)
      var out = device
      out.idx = idx
      deviceMap[idx] = out
      return out
    }
  }

  private func lookupDevice(idx: String) -> DeviceInfo? {
    _ = buildDeviceList()
    return deviceMap[idx]
  }

  // MARK: - App Handling

  private func handleRequestApps(deviceId: String) async -> WCReply {
    Log.debug("iPhone", "📲 Watch requested apps for device: \(deviceId)")

    // Get apps from cache
    let initialApps: [RokuApp] = await MainActor.run {
      let cache = AppCacheManager.shared
      let apps = cache.apps(for: deviceId)

      Log.debug("iPhone", "📱 Found \(apps.count) cached apps for \(deviceId)")

      let mruDict: [String: TimeInterval] = Dictionary(
        uniqueKeysWithValues: apps.compactMap { app in
          guard let lastUsed = cache.lastUsedAt(appId: app.id, deviceId: deviceId) else { return nil }
          return (app.id, lastUsed.timeIntervalSince1970)
        }
      )

      sendToWatch(.event(.appList(WCAppListEvent(deviceId: deviceId, apps: apps, mru: mruDict))))

      // If no apps cached, fetch them
      if apps.isEmpty {
        Log.debug("iPhone", "📡 No apps cached, fetching from device...")
        if RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId }) == nil {
          Log.warn("iPhone", "Device not found: \(deviceId)")
        }
      }
      return apps
    }

    if initialApps.isEmpty,
       let device = RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId }) {
      await MainActor.run {
        Log.debug("iPhone", "📡 Fetching apps from device: \(device.name)")
      }
      await AppCacheManager.shared.fetchApps(for: device.id, deviceName: device.name)

      // Send updated list.
      let newApps = await MainActor.run { AppCacheManager.shared.apps(for: deviceId) }
      let mruDict: [String: TimeInterval] = await MainActor.run {
        Dictionary(
          uniqueKeysWithValues: newApps.compactMap { app in
            guard let lastUsed = AppCacheManager.shared.lastUsedAt(appId: app.id, deviceId: deviceId) else { return nil }
            return (app.id, lastUsed.timeIntervalSince1970)
          }
        )
      }
      sendToWatch(.event(.appList(WCAppListEvent(deviceId: deviceId, apps: newApps, mru: mruDict))))
      return .appsAck(count: newApps.count)
    }

    return .appsAck(count: initialApps.count)
  }

  private func handleLaunchApp(deviceId: String?, deviceIdx: String?, appId: String) async -> WCReply {
    let device: DeviceInfo? = {
      if let deviceId {
        return RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId })
      }
      if let deviceIdx {
        return deviceMap[deviceIdx] ?? lookupDevice(idx: deviceIdx)
      }
      return nil
    }()

    guard let device else {
      Log.noisy(
        "iPhoneWC",
        "launchApp: unknown device deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil") appId=\(appId)")
      return .error("unknown device")
    }

    Log.noisy(
      "iPhoneWC",
      "launchApp: forwarding to Roku appId=\(appId) deviceId=\(device.id) name='\(device.name)'")
    let success = await RokuECPClient.shared.launchApp(appId: appId, device: device)
    Log.noisy(
      "iPhoneWC",
      "launchApp: RokuECPClient result=\(success ? "ok" : "fail") appId=\(appId) deviceId=\(device.id)")
    return success ? .ok : .error("launch failed")
  }

  private func handleRequestIcon(_ req: WCIconRequest) async -> WCReply {
    let deviceId = req.deviceId
    let appId = req.appId
    let watchHash = req.hash

    if let (data, hash) = await getIconWithHash(appId: appId, deviceId: deviceId) {
      if hash != watchHash {
        sendIconDataToWatch(appId: appId, deviceId: deviceId, data: data, hash: hash)
        return .iconStatus(.sent)
      }
      return .iconStatus(.unchanged)
    }
    return .iconStatus(.notFound)
  }

  private func handleRequestIconsBatch(_ req: WCIconsBatchRequest) async -> WCReply {
    let deviceId = req.deviceId
    Log.debug("iPhone", "📦 Batch icon request: \(req.ordered.count) apps, deviceId=\(deviceId)")

    var sentCount = 0
    var unchangedCount = 0

    for pair in req.ordered {
      // If the watch fell off reachability mid-batch, stop early.
      if session?.isReachable != true { break }

      let appId = pair.appId
      let watchHash = pair.hash
      if let (data, hash) = await getIconWithHash(appId: appId, deviceId: deviceId) {
        if hash != watchHash {
          sendIconDataToWatch(appId: appId, deviceId: deviceId, data: data, hash: hash)
          sentCount += 1

          // WCSession can drop messages if we firehose too fast; a tiny yield helps reliability.
          if sentCount % 4 == 0 {
            try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
          }
        } else {
          unchangedCount += 1
        }
      }
    }

    Log.debug("iPhone", "📦 Batch complete: sent=\(sentCount), unchanged=\(unchangedCount)")
    return .iconsBatchAck(sent: sentCount, unchanged: unchangedCount)
  }

  /// Get icon data and its SHA-1 hash (fetches from Roku if not cached)
  /// Hash is of ORIGINAL data - computed once when fetched, never recomputed
  @MainActor
  private func getIconWithHash(appId: String, deviceId: String) async -> (Data, String)? {
    let cache = AppCacheManager.shared

    // Try cached icon first - use stored hash
    if let iconData = cache.iconData(for: appId, deviceId: deviceId),
       let resized = resizeIconForWatch(iconData) {
      let hash = cache.iconHash(for: appId, deviceId: deviceId)
      // If no hash stored (legacy), compute it now
      let finalHash = hash.isEmpty ? AppCacheManager.sha1(iconData) : hash
      return (resized, finalHash)
    }

    // Fetch from Roku - AppCacheManager stores hash when saving
    if let device = RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId }),
       let iconData = await RokuECPClient.shared.fetchAppIcon(appId: appId, device: device) {
      // Save to cache (this computes and stores hash)
      let app = RokuApp(id: appId, name: "", type: nil, version: nil)
      await cache.saveIconAsync(data: iconData, for: app, deviceId: deviceId)

      // Now resize for Watch
      if let resized = resizeIconForWatch(iconData) {
        let hash = cache.iconHash(for: appId, deviceId: deviceId)
        return (resized, hash)
      }
    }

    return nil
  }

  /// Send icon as binary data with header: "appId|deviceId|hash|" + imageData
  private func sendIconDataToWatch(appId: String, deviceId: String, data: Data, hash: String) {
    guard let session = session, session.isReachable else {
      Log.debug("iPhone", "sendIconDataToWatch: session not reachable for appId=\(appId)")
      return
    }

    let header = "\(appId)|\(deviceId)|\(hash)|"
    var payload = Data(header.utf8)
    payload.append(data)

    Log.debug(
      "iPhone",
      "📤 Sending icon: appId=\(appId), hash=\(hash.prefix(8))..., size=\(data.count) bytes"
    )

    session.sendMessageData(payload, replyHandler: nil) { error in
      Log.error("iPhone", "Send icon error: \(error.localizedDescription)")
    }
  }

  /// Resize icon to watch-appropriate size (200×150 px, 4:3 canvas)
  private func resizeIconForWatch(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    // Target: 200×150 pixels (4:3 ratio, crisp for grid and strip display)
    let targetSize = CGSize(width: 200, height: 150)

    UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
    // Preserve aspect ratio and top-align so wide icons naturally leave room at the bottom
    // (Roku uses wide icons to imply “label in bottom strip”).
    let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = CGRect(origin: .zero, size: drawSize)
    image.draw(in: drawRect)
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    // Use PNG to preserve transparency (Roku icons often have transparent backgrounds)
    return resized?.pngData()
  }

  // MARK: - Send to Watch

  private func sendToWatch(_ message: WCWireMessage) {
    guard let session = session, session.isReachable else { return }
    do {
      let payload = try WCWireCodec.encode(message)
      session.sendMessageData(payload, replyHandler: nil) { error in
        Log.error("iPhone", "Send to Watch error: \(error.localizedDescription)")
      }
    } catch {
      Log.error("iPhone", "Failed to encode WCWireMessage: \(error.localizedDescription)")
    }
  }

  /// Persist a snapshot for watch complications/widgets via applicationContext.
  /// This does not require reachability and is available on the watch at next activation.
  private func updateWatchApplicationContext() {
    guard let session else { return }
    guard session.activationState == .activated else { return }

    let discovery = RokuDiscoveryService.shared
    _ = discovery.discoveredDevices

    let devicesWithIdx = buildDeviceList()
    let statesById: [String: DeviceState] = Dictionary(
      uniqueKeysWithValues: devicesWithIdx.map { ($0.id, DeviceStateManager.shared.state(for: $0.id)) }
    )
    let snapshot = WatchSurfaceSnapshot(
      generatedAt: Date().timeIntervalSince1970,
      devices: devicesWithIdx,
      deviceStates: statesById
    )
    let context = WCApplicationContext(snapshot: snapshot, settings: AppSettings.shared.watchConnectivitySettings)
    let contextData = (try? JSONEncoder().encode(context)) ?? Data()

    do {
      try session.updateApplicationContext([
        WCApplicationContext.key: contextData
      ])
    } catch {
      DebugBuild.run {
        Log.warn("iPhoneWC", "updateApplicationContext failed: \(error.localizedDescription)")
      }
    }
  }

  /// Push device list to watch
  private func pushDeviceListToWatch() {
    let devices = buildDeviceList()
    guard !devices.isEmpty else { return }
    sendToWatch(.event(.deviceList(WCDeviceListEvent(devices: devices, settings: AppSettings.shared.watchConnectivitySettings))))
  }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

  nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    if let error = error {
      Log.error("iPhone", "WCSession activation failed: \(error.localizedDescription)")
    }
    Task { @MainActor in
      self.isWatchReachable = session.isReachable
      self.isPaired = session.isPaired
      self.isWatchAppInstalled = session.isWatchAppInstalled
      self.updateConfigurationState(session: session, receivedMessage: false)
    }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    Task { @MainActor in
      self.isWatchReachable = session.isReachable
      self.isPaired = session.isPaired
      self.isWatchAppInstalled = session.isWatchAppInstalled

      // When watch becomes reachable, send it the device list and current power states
      if session.isReachable {
        AppSettings.shared.syncNow()
        self.scheduleDeviceListUpdate()
        self.pushAllDeviceStates()
      }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
    Task { @MainActor in
      self.updateConfigurationState(session: session, receivedMessage: true)
      do {
        let msg = try WCWireCodec.decode(messageData)
        guard case .request(let request) = msg else { return }
        _ = await self.handleWatchRequest(request)
      } catch {
        Log.warn("iPhoneWC", "Failed to decode WC request: \(error.localizedDescription)")
      }
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveMessageData messageData: Data,
    replyHandler: @escaping (Data) -> Void
  ) {
    Task { @MainActor in
      self.updateConfigurationState(session: session, receivedMessage: true)
      do {
        let msg = try WCWireCodec.decode(messageData)
        guard case .request(let request) = msg else { return }
        let reply = await self.handleWatchRequest(request)
        let replyData = try WCWireCodec.encode(.reply(reply))
        replyHandler(replyData)
      } catch {
        Log.warn("iPhoneWC", "Failed to decode WC request: \(error.localizedDescription)")
        if let replyData = try? WCWireCodec.encode(.reply(.error("decode failed"))) {
          replyHandler(replyData)
        }
      }
    }
  }
}

// MARK: - Configuration Diagnostics

extension WatchConnectivityManager {

  /// Check for configuration issues and update published state
  fileprivate func updateConfigurationState(session: WCSession, receivedMessage: Bool) {
    // If we received a message but system says Watch app isn't installed, we have a problem
    if receivedMessage && !session.isWatchAppInstalled {
      if configurationIssue != .watchAppNotEmbedded {
        Log.warn("iPhone", "Watch app not properly embedded in iPhone app bundle")
        configurationIssue = .watchAppNotEmbedded
      }
    }
    // Not paired at all
    else if !session.isPaired {
      configurationIssue = .notPaired
    }
    // Everything looks good - clear any previous issue
    else if session.isWatchAppInstalled && session.isPaired {
      configurationIssue = nil
    }
  }

  /// Dismiss the current configuration issue (user acknowledged it)
  func dismissConfigurationIssue() {
    configurationIssue = nil
  }
}
