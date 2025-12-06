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
            self.sendToWatch([
              "type": "mruUpdate",
              "deviceId": deviceId,
              "mru": mruDict,
            ])
          }
        }
    }
  }

  /// Push device state to watch
  private func pushStateToWatch(deviceId: String, state: DeviceState) {
    sendToWatch([
      "type": "deviceState",
      "deviceId": deviceId,
      "state": state.toDictionary()
    ])
  }

  /// Push all known device states to watch (called when watch becomes reachable)
  private func pushAllDeviceStates() {
    for device in RokuDiscoveryService.shared.discoveredDevices {
      let state = DeviceStateManager.shared.state(for: device.id)
      sendToWatch([
        "type": "deviceState",
        "deviceId": device.id,
        "state": state.toDictionary()
      ])
    }
  }

  /// Debounced device list push - coalesces rapid updates
  private func scheduleDeviceListUpdate() {
    deviceUpdateTask?.cancel()
    deviceUpdateTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 sec debounce
      guard !Task.isCancelled else { return }
      pushDeviceListToWatch()
    }
  }

  // MARK: - Message Handling

  private func handleWatchMessage(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    guard let type = message["type"] as? String else {
      reply(["error": "missing type"])
        return
      }

      Log.noisy("iPhoneWC", "handle type=\(type)")

    switch type {
    case "handshake", "requestDevices":
      Task {
        let devices = await buildDeviceListWaitingForDiscovery()
        let settings = AppSettings.shared
        reply([
          "status": "ok",
          "devices": devices,
          "settings": [
            "watchPowerDelay": settings.watchPowerDelay ?? 0.0,
            "phonePowerDelay": settings.phonePowerDelay ?? 0.0,
            "watchHomeDelay": settings.watchHomeDelay ?? 0.0,
            "phoneHomeDelay": settings.phoneHomeDelay ?? 0.0,
              "watchAppLaunchDelay": settings.watchAppLaunchDelay ?? 0.0,
              "phoneAppLaunchDelay": settings.phoneAppLaunchDelay ?? 0.0,
            "watchLaunchScreen": settings.watchLaunchScreen.rawValue,
            "watchAlwaysLaunchToMedia": settings.watchAlwaysLaunchToMedia,
          ],
        ])
      }

    case "keypress":
      handleKeypress(message, reply: reply)

    case "requestApps":
      handleRequestApps(message, reply: reply)

    case "launchApp":
      handleLaunchApp(message, reply: reply)

    case "requestIcon":
      handleRequestIcon(message, reply: reply)

    case "requestIconsBatch":
      handleRequestIconsBatch(message, reply: reply)

    default:
      reply(["error": "unknown type"])
    }
  }

  /// Wait for discovery to complete if it's running and we have no devices yet
  private func buildDeviceListWaitingForDiscovery() async -> [[String: Any]] {
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

  private func handleKeypress(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    let now = Date()
      guard let key = message["key"] as? String else {
        reply(["error": "missing key"])
        return
      }

      let deviceId = message["deviceId"] as? String
      let deviceIdx = message["device"] as? String

      Log.noisy(
        "iPhoneWC",
        "keypress: received key=\(key) deviceId=\(deviceId ?? "nil") deviceIdx=\(deviceIdx ?? "nil")")

    // Throttle: skip if less than 200ms since last keypress
    let elapsed = now.timeIntervalSince(lastKeypressTime)
    if elapsed < keypressThrottleInterval {
      Log.debug("iPhone", "⏭️ Keypress throttled: \(key) (only \(Int(elapsed * 1000))ms since last)")
      reply(["status": "throttled"])
      return
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
      reply(["error": "unknown device"])
      return
    }

    // Send keypress via RokuECPClient (WebSocket first, HTTP fallback)
    Task {
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
      reply(success ? ["status": "ok"] : ["error": "keypress failed"])
    }
  }

  private func buildDeviceList() -> [[String: Any]] {
    let devices = RokuDiscoveryService.shared.discoveredDevices
    deviceMap.removeAll()

    var result: [[String: Any]] = []
    for (index, device) in devices.enumerated() {
      let idx = String(index + 1)
      deviceMap[idx] = device

      var entry: [String: Any] = [
        "idx": idx,
        "id": device.id,
        "name": device.name,
        "ip": device.ipAddress,
        "isTV": device.isTV,
        "deviceType": device.isTV ? "tv" : "streamer"
      ]
      if let location = device.location {
        entry["location"] = location
      }
      result.append(entry)
    }
    return result
  }

  private func lookupDevice(idx: String) -> DeviceInfo? {
    let devices = RokuDiscoveryService.shared.discoveredDevices
    for (index, device) in devices.enumerated() {
      deviceMap[String(index + 1)] = device
    }
    return deviceMap[idx]
  }

  // MARK: - App Handling

  private func handleRequestApps(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    guard let deviceId = message["deviceId"] as? String else {
      Log.warn("iPhone", "requestApps: missing deviceId")
      reply(["error": "missing deviceId"])
      return
    }

    Log.debug("iPhone", "📲 Watch requested apps for device: \(deviceId)")

    // Get apps from cache
    Task { @MainActor in
      let cache = AppCacheManager.shared
      let apps = cache.apps(for: deviceId)

      Log.debug("iPhone", "📱 Found \(apps.count) cached apps for \(deviceId)")

      let appDicts: [[String: Any]] = apps.map { app in
        ["id": app.id, "name": app.name, "type": app.type ?? ""]
        }

        // Get MRU data for this device - build dict from public API
        var mruDict: [String: TimeInterval] = [:]
        for app in apps {
          if let lastUsed = cache.lastUsedAt(appId: app.id, deviceId: deviceId) {
            mruDict[app.id] = lastUsed.timeIntervalSince1970
          }
        }

        // Send apps and MRU to watch
        sendToWatch([
          "type": "appList",
          "deviceId": deviceId,
          "apps": appDicts,
          "mru": mruDict,  // Include MRU so watch can sort properly
        ])
      reply(["status": "ok", "count": apps.count])

      // If no apps cached, fetch them
      if apps.isEmpty {
        Log.debug("iPhone", "📡 No apps cached, fetching from device...")
        if let device = RokuDiscoveryService.shared.discoveredDevices.first(where: { $0.id == deviceId }) {
          await cache.fetchApps(for: device.id, deviceName: device.name)
          // Send again after fetch
          let newApps = cache.apps(for: deviceId)
          Log.debug("iPhone", "✅ Fetched \(newApps.count) apps, sending to watch")
          let newDicts: [[String: Any]] = newApps.map { ["id": $0.id, "name": $0.name, "type": $0.type ?? ""]
            }
            // Include MRU again
            var newMruDict: [String: TimeInterval] = [:]
            for app in newApps {
              if let lastUsed = cache.lastUsedAt(appId: app.id, deviceId: deviceId) {
                newMruDict[app.id] = lastUsed.timeIntervalSince1970
              }
            }
            sendToWatch([
              "type": "appList",
              "deviceId": deviceId,
              "apps": newDicts,
              "mru": newMruDict
          ])
        } else {
          Log.warn("iPhone", "Device not found: \(deviceId)")
        }
      }
    }
  }

  private func handleLaunchApp(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void)
    {
      guard let appId = message["appId"] as? String else {
        reply(["error": "missing appId"])
        return
      }

      let deviceId = message["deviceId"] as? String
      let deviceIdx = message["device"] as? String

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
      reply(["error": "unknown device"])
        return
      }

      Task {
        Log.noisy(
          "iPhoneWC",
          "launchApp: forwarding to Roku appId=\(appId) deviceId=\(device.id) name='\(device.name)'")
      let success = await RokuECPClient.shared.launchApp(appId: appId, device: device)
        Log.noisy(
          "iPhoneWC",
          "launchApp: RokuECPClient result=\(success ? "ok" : "fail") appId=\(appId) deviceId=\(device.id)")
      reply(success ? ["status": "ok"] : ["error": "launch failed"])
    }
  }

  private func handleRequestIcon(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    guard let deviceId = message["deviceId"] as? String,
          let appId = message["appId"] as? String else {
      reply(["error": "missing deviceId or appId"])
      return
    }

    let watchHash = message["hash"] as? String ?? ""

    Task { @MainActor in
      // Try to get and send icon (with hash comparison)
      if let (data, hash) = await getIconWithHash(appId: appId, deviceId: deviceId) {
        // Only send if hash differs
        if hash != watchHash {
          sendIconDataToWatch(appId: appId, deviceId: deviceId, data: data, hash: hash)
          reply(["status": "sent"])
        } else {
          reply(["status": "unchanged"])
        }
      } else {
        reply(["error": "icon not found"])
      }
    }
  }

  private func handleRequestIconsBatch(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
    guard let deviceId = message["deviceId"] as? String else {
      reply(["error": "missing deviceId"])
      return
    }

    // Support both ordered array (new) and dictionary (legacy)
    var orderedPairs: [(String, String)] = []

    if let ordered = message["orderedHashes"] as? [[String]] {
      // New format: array of [appId, hash] pairs - preserves display order
      orderedPairs = ordered.compactMap { pair in
        guard pair.count >= 2 else { return nil }
        return (pair[0], pair[1])
      }
    } else if let hashes = message["hashes"] as? [String: String] {
      // Legacy format: dictionary (unordered)
      orderedPairs = hashes.map { ($0.key, $0.value) }
    } else {
      reply(["error": "missing hashes"])
      return
    }

    Log.debug("iPhone", "📦 Batch icon request: \(orderedPairs.count) apps, deviceId=\(deviceId)")

    Task { @MainActor in
      var sentCount = 0
      var unchangedCount = 0

      for (appId, watchHash) in orderedPairs {
        if let (data, hash) = await getIconWithHash(appId: appId, deviceId: deviceId) {
          if hash != watchHash {
            sendIconDataToWatch(appId: appId, deviceId: deviceId, data: data, hash: hash)
            sentCount += 1
          } else {
            unchangedCount += 1
          }
        }
      }

      Log.debug("iPhone", "📦 Batch complete: sent=\(sentCount), unchanged=\(unchangedCount)")
      reply(["status": "ok", "sent": sentCount, "unchanged": unchangedCount])
    }
  }

  /// Get icon data and its SHA-1 hash (fetches from Roku if not cached)
  /// Hash is of ORIGINAL data - computed once when fetched, never recomputed
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

  private func sendToWatch(_ message: [String: Any]) {
    guard let session = session, session.isReachable else { return }
    session.sendMessage(message, replyHandler: nil) { error in
      Log.error("iPhone", "Send to Watch error: \(error.localizedDescription)")
    }
  }

  /// Push device list to watch
  private func pushDeviceListToWatch() {
    let devices = buildDeviceList()
    guard !devices.isEmpty else { return }
    sendToWatch(["type": "deviceList", "devices": devices])
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

  // Message without reply handler
  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    Task { @MainActor in
      self.updateConfigurationState(session: session, receivedMessage: true)
          let t = message["type"] as? String ?? "?"
          Log.noisy("iPhoneWC", "didReceiveMessage type=\(t) keys=\(Array(message.keys).sorted())")
      self.handleWatchMessage(message) { _ in }
    }
  }

  // Message with reply handler
  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    Task { @MainActor in
      self.updateConfigurationState(session: session, receivedMessage: true)
          let t = message["type"] as? String ?? "?"
          Log.noisy(
            "iPhoneWC", "didReceiveMessage(reply) type=\(t) keys=\(Array(message.keys).sorted())")
      self.handleWatchMessage(message, reply: replyHandler)
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
