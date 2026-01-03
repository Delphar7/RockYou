// RokuWebSocketClient.swift
// RockYou - MIT License
//
// Clean-room implementation of Roku's ecp-2 WebSocket protocol
// using Apple's Network framework for consistency with discovery.

import Foundation
import Network
import os.lock

// MARK: - Notification Types
// Note: Device state is now managed by shared DeviceStateManager

enum RokuNotification: Sendable {
  case powerModeChanged(String)
  case volumeChanged(Int, muted: Bool)
  case mediaPlayerStateChanged(
    String, appId: String?, position: Int?, duration: Int?, title: String?)
  case other(String, [String: String])
}

// MARK: - WebSocket Client

/// Authenticated WebSocket client for Roku ECP-2 protocol
/// Uses NWConnection with WebSocket for consistency with discovery service
actor RokuWebSocketClient {

  // MARK: - Types

  enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case subscribing
    case connected
    case failed(String)
  }

  enum ECPError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case sendFailed(String)
    case timeout
    case invalidResponse
    case notConnected
    case deviceOff

    var errorDescription: String? {
      switch self {
      case .connectionFailed(let msg): return "Connection failed: \(msg)"
      case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
      case .sendFailed(let msg): return "Send failed: \(msg)"
      case .timeout: return "Request timed out"
      case .invalidResponse: return "Invalid response from device"
      case .notConnected: return "Not connected to device"
      case .deviceOff: return "Device is powered off"
      }
    }
  }

  // MARK: - Authentication Constants

  /// The authentication key used for ecp-2 challenge-response
  private static let authKey = "<ECP2-AUTH-KEY-REDACTED>"

  /// Transform a character for auth key derivation
  private static nonisolated func charTransform(_ char: UInt8, _ shift: UInt8) -> UInt8 {
    let value: UInt8
    if char >= UInt8(ascii: "0") && char <= UInt8(ascii: "9") {
      value = char - UInt8(ascii: "0")
    } else if char >= UInt8(ascii: "A") && char <= UInt8(ascii: "F") {
      value = char - UInt8(ascii: "A") + 10
    } else {
      return char
    }

    var result = (15 - value + shift) & 15
    if result < 10 {
      result += UInt8(ascii: "0")
    } else {
      result = result + UInt8(ascii: "A") - 10
    }
    return result
  }

  /// Derive the auth seed from the key
  private static nonisolated var authSeed: Data {
    Data(authKey.utf8.map { charTransform($0, 9) })
  }

  /// Compute the challenge response
  private static nonisolated func computeAuthResponse(challenge: String) -> String {
    let data = challenge.data(using: .utf8)! + authSeed
    return SHA1.digest(data).base64EncodedString()
  }

  // MARK: - Event Subscriptions

  /// Events to subscribe to after authentication
  private static let eventSubscriptions = [
    "+power-mode-changed",
    "+volume-changed",
    "+media-player-state-changed",
  ].joined(separator: ",")

  // MARK: - Properties

  private let deviceIP: String
  private let deviceName: String
  private var connection: NWConnection?
  private var state: ConnectionState = .disconnected
  private var requestCounter: Int = 2  // Start at 2 (1 is reserved for auth)
  private var pendingResponses: [String: CheckedContinuation<ECPResponseMsg, Error>] = [:]
  private var pendingResponseTimeoutTasks: [String: Task<Void, Never>] = [:]
  private var receiveTask: Task<Void, Never>?
  private let queue = DispatchQueue(label: "com.rockyou.websocket", qos: .userInitiated)

  /// Callback for device state updates (always called on MainActor)
  private var onNotification: (@MainActor (RokuNotification) -> Void)?

  // MARK: - Initialization

  init(
    deviceIP: String, deviceName: String = "Unknown",
    onNotification: (@MainActor (RokuNotification) -> Void)? = nil
  ) {
    self.deviceIP = deviceIP
    self.deviceName = deviceName
    self.onNotification = onNotification
  }

  /// Update the notification handler
  func setNotificationHandler(_ handler: @escaping @MainActor (RokuNotification) -> Void) {
    self.onNotification = handler
  }

  // MARK: - Connection Management

  /// Connect to the device, authenticate, and subscribe to events
  func connect() async throws {
    guard state == .disconnected || state.isFailed else {
      if state == .connected { return }
      throw ECPError.connectionFailed("Already connecting")
    }

    state = .connecting

    // Create WebSocket URL with the ecp-session path
    guard let url = URL(string: "ws://\(deviceIP):8060/ecp-session") else {
      throw ECPError.connectionFailed("Invalid URL")
    }

    // Configure WebSocket with ecp-2 subprotocol
    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true
    wsOptions.setSubprotocols(["ecp-2"])

    // Use TCP parameters (ws:// not wss://)
    let parameters = NWParameters.tcp
    parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

    // Create connection using URL endpoint (includes path!)
    let conn = NWConnection(to: .url(url), using: parameters)
    self.connection = conn

    // Wait for connection to be ready
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let resumed = OSAllocatedUnfairLock(initialState: false)
      conn.stateUpdateHandler = { newState in
        switch newState {
        case .ready:
          let shouldResume = resumed.withLock { alreadyResumed in
            if alreadyResumed { return false }
            alreadyResumed = true
            return true
          }
          guard shouldResume else { return }
          continuation.resume()
        case .failed(let error):
          let shouldResume = resumed.withLock { alreadyResumed in
            if alreadyResumed { return false }
            alreadyResumed = true
            return true
          }
          guard shouldResume else { return }
          continuation.resume(throwing: ECPError.connectionFailed(error.localizedDescription))
        case .cancelled:
          let shouldResume = resumed.withLock { alreadyResumed in
            if alreadyResumed { return false }
            alreadyResumed = true
            return true
          }
          guard shouldResume else { return }
          continuation.resume(throwing: ECPError.connectionFailed("Connection cancelled"))
        default:
          break
        }
      }
      conn.start(queue: queue)
    }

    // Update state handler for ongoing monitoring
    conn.stateUpdateHandler = { [weak self] newState in
      guard let self = self else { return }
      Task {
        if case .failed(let error) = newState {
          await self.handleConnectionFailure(error.localizedDescription)
        } else if case .cancelled = newState {
          await self.setState(.disconnected)
        }
      }
    }

    // Perform authentication
    state = .authenticating
    try await handleAuthentication()

    // Start receive loop BEFORE subscribing (so we get the response)
    receiveTask = Task { [weak self] in
      await self?.receiveLoop()
    }

    // Subscribe to events
    state = .subscribing
    try await subscribeToEvents()

    state = .connected
    Log.info("RokuWS", "✅ Connected to \(deviceName) at \(deviceIP)")
  }

  private func setState(_ newState: ConnectionState) {
    self.state = newState
  }

  private func handleConnectionFailure(_ error: String) {
    state = .failed(error)
    failAllPendingResponses(with: ECPError.connectionFailed(error))
  }

  /// Disconnect from the device
  func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    connection?.cancel()
    connection = nil

    failAllPendingResponses(with: ECPError.notConnected)

    state = .disconnected
  }

  /// Check if connected
  var isConnected: Bool {
    state == .connected
  }

  // MARK: - Authentication

  private func handleAuthentication() async throws {
    guard let conn = connection else {
      throw ECPError.connectionFailed("No connection")
    }

    // Receive authentication challenge
    let challengeData = try await receiveWebSocketMessage(from: conn)

    // Parse challenge
    guard let challenge = try? JSONDecoder().decode(AuthChallenge.self, from: challengeData) else {
      let json = String(data: challengeData, encoding: .utf8) ?? "?"
      throw ECPError.authenticationFailed("Failed to parse challenge: \(json)")
    }

    // Compute response
    let response = Self.computeAuthResponse(challenge: challenge.paramChallenge)

    // Build authentication response JSON manually to ensure correct key format
    let authJSON = """
      {"param-microphone-sample-rates":"16000","param-response":"\(response)","request-id":"1","param-client-friendly-name":"RockYou Remote","request":"authenticate","param-has-microphone":"false"}
      """

    // Send authentication response
    try await sendWebSocketMessage(authJSON, to: conn)

    // Receive authentication result
    let resultData = try await receiveWebSocketMessage(from: conn)
    guard let resultJSON = String(data: resultData, encoding: .utf8) else {
      throw ECPError.authenticationFailed("Invalid auth result encoding")
    }

    // Parse result - check for status 200
    if !resultJSON.contains("\"status\":\"200\"") {
      throw ECPError.authenticationFailed("Auth failed: \(resultJSON)")
    }
  }

  // MARK: - Event Subscription

  private func subscribeToEvents() async throws {
    guard let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let subscribeJSON = """
      {"request":"request-events","request-id":"\(requestId)","param-events":"\(Self.eventSubscriptions)"}
      """

    // Send subscription request and wait for acknowledgment (with timeout)
    let response = try await sendRequestWithTimeout(
      subscribeJSON, to: conn, requestId: requestId, timeout: 5)

    // 200 = OK, 202 = Accepted (busy but will process)
    guard response.status == "200" || response.status == "202" else {
      Log.warn(
        "RokuWS",
        "⚠️ Event subscription failed: status=\(response.status), msg=\(response.statusMsg ?? "none")"
      )
      Log.warn("RokuWS", "⚠️ Attempted to subscribe to: \(Self.eventSubscriptions)")
      // Don't throw - subscription failure shouldn't prevent usage
      return
    }

    Log.info(
      "RokuWS",
      "✅ Event subscription acknowledged: status=\(response.status), events=\(Self.eventSubscriptions)"
    )
  }

  // MARK: - WebSocket I/O

  private func sendWebSocketMessage(_ text: String, to conn: NWConnection) async throws {
    Log.noisy("RokuWS", "➡️ \(text)")
    let data = Data(text.utf8)
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(identifier: "ecpMessage", metadata: [metadata])

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      conn.send(
        content: data, contentContext: context, isComplete: true,
        completion: .contentProcessed { error in
          if let error = error {
            continuation.resume(throwing: ECPError.sendFailed(error.localizedDescription))
          } else {
            continuation.resume()
          }
        })
    }
  }

  private func receiveWebSocketMessage(from conn: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      conn.receiveMessage { content, context, isComplete, error in
        if let error = error {
          continuation.resume(throwing: ECPError.connectionFailed(error.localizedDescription))
          return
        }

        guard let data = content else {
          continuation.resume(throwing: ECPError.invalidResponse)
          return
        }

        continuation.resume(returning: data)
      }
    }
  }

  // MARK: - Message Loop

  private func receiveLoop() async {
    guard let conn = connection else { return }

    while !Task.isCancelled && (state == .connected || state == .subscribing) {
      do {
        let data = try await receiveWebSocketMessage(from: conn)
        await handleReceivedData(data)
      } catch {
        if !Task.isCancelled {
          Log.error("RokuWS", "Receive error: \(error.localizedDescription)")
          state = .failed(error.localizedDescription)
        }
        break
      }
    }
  }

  private func handleReceivedData(_ data: Data) async {
    guard let json = String(data: data, encoding: .utf8) else { return }

    // Logging note:
    // Many ECP2 responses include a `"content-data"` field which is base64-encoded. When we print
    // `json.prefix/suffix`, we end up effectively dumping the *base64 string* head/tail, which is
    // not what we want when debugging actual payload bytes. Prefer logging the decoded head/tail.
    if json.contains("\"content-data\""),
      let response = try? JSONDecoder().decode(ECPResponseMsg.self, from: data),
      let decoded = response.decodedContentData
    {
      let head = Self.hexPrefix(decoded, maxBytes: 12)
      let tail = Self.hexSuffix(decoded, maxBytes: 12)
      let contentType = response.contentType ?? ""
      Log.noisy(
        "RokuWS",
        "⬅️ resp=\(response.response) id=\(response.responseId) status=\(response.status) type=\(contentType) content(decoded)=\(decoded.count)B head=\(head) tail=\(tail)"
      )
    } else {
      Log.noisy("RokuWS", "⬅️ \(json.prefix(40))...\(json.suffix(10))")
    }

    // Try to parse as response (has "response-id")
    if json.contains("\"response-id\"") {
      if let response = try? JSONDecoder().decode(ECPResponseMsg.self, from: data) {
        // Check for explorer fire-and-forget handler first
        if let handler = explorerResponseHandlers.removeValue(forKey: response.responseId) {
          await MainActor.run {
            handler(json)
          }
        }
        // Then check for regular pending response
        finishPendingResponse(id: response.responseId, result: .success(response))
        return
      }
    }

    // Try to parse as notification (has "notify")
    if json.contains("\"notify\"") {
      Log.noisy("RokuWS", "📩 Notification received (full JSON): \(json)")
      if let notification = parseNotification(json: json, data: data) {
        Log.info("RokuWS", "📩 Parsed notification: \(String(describing: notification))")
        // Dispatch to handler
        if let handler = onNotification {
          Log.info(
            "RokuWS", "🔄 Calling notification handler for: \(String(describing: notification))")
          await MainActor.run {
            handler(notification)
          }
        } else {
          Log.warn("RokuWS", "⚠️ No notification handler set!")
        }
      } else {
        Log.warn("RokuWS", "⚠️ Failed to parse notification from: \(json)")
      }
      return
    }
  }

  private static func hexPrefix(_ data: Data, maxBytes: Int) -> String {
    Self.hexBytes(data.prefix(maxBytes))
  }

  private static func hexSuffix(_ data: Data, maxBytes: Int) -> String {
    Self.hexBytes(data.suffix(maxBytes))
  }

  private static func hexBytes(_ bytes: Data.SubSequence) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }

  private func parseNotification(json: String, data: Data) -> RokuNotification? {
    // Extract notify type
    guard let notifyStart = json.range(of: "\"notify\":\""),
      let notifyEnd = json[notifyStart.upperBound...].range(of: "\"")
    else {
      return nil
    }

    let notifyType = String(json[notifyStart.upperBound..<notifyEnd.lowerBound])

    switch notifyType {
    case "power-mode-changed":
      // Extract param-power-mode
      if let modeStart = json.range(of: "\"param-power-mode\":\""),
        let modeEnd = json[modeStart.upperBound...].range(of: "\"")
      {
        let mode = String(json[modeStart.upperBound..<modeEnd.lowerBound])
        return .powerModeChanged(mode)
      }

    case "volume-changed":
      // Extract param-volume and param-muted
      var volume = 0
      var muted = false
      if let volStart = json.range(of: "\"param-volume\":\""),
        let volEnd = json[volStart.upperBound...].range(of: "\"")
      {
        volume = Int(json[volStart.upperBound..<volEnd.lowerBound]) ?? 0
      }
      if json.contains("\"param-mute\":\"true\"") {
        muted = true
      }
      return .volumeChanged(volume, muted: muted)

    case "media-player-state-changed":
      Log.noisy("RokuWS", "📦 media-player-state-changed raw: \(json)")

      // Extract param-media-player-state (not param-state)
      var state: String? = nil
      if let stateStart = json.range(of: "\"param-media-player-state\":\""),
        let stateEnd = json[stateStart.upperBound...].range(of: "\"")
      {
        state = String(json[stateStart.upperBound..<stateEnd.lowerBound])
      }

      // Also extract param-channel-id (app ID) - this tells us which app is active
      var appId: String? = nil
      if let channelStart = json.range(of: "\"param-channel-id\":\""),
        let channelEnd = json[channelStart.upperBound...].range(of: "\"")
      {
        appId = String(json[channelStart.upperBound..<channelEnd.lowerBound])
      }

      // Extract position (in milliseconds)
      var position: Int? = nil
      if let posStart = json.range(of: "\"param-media-player-position\":\""),
        let posEnd = json[posStart.upperBound...].range(of: " ms\"")
      {
        let posStr = String(json[posStart.upperBound..<posEnd.lowerBound])
        position = Int(posStr)
      }

      // Extract duration (in milliseconds)
      var duration: Int? = nil
      if let durStart = json.range(of: "\"param-media-player-duration\":\""),
        let durEnd = json[durStart.upperBound...].range(of: " ms\"")
      {
        let durStr = String(json[durStart.upperBound..<durEnd.lowerBound])
        duration = Int(durStr)
      }

      // Extract channel title (app name, e.g., "Netflix")
      var title: String? = nil
      if let titleStart = json.range(of: "\"param-channel-title\":\""),
        let titleEnd = json[titleStart.upperBound...].range(of: "\"")
      {
        title = String(json[titleStart.upperBound..<titleEnd.lowerBound])
      }

      Log.info(
        "RokuWS",
        "📱 Extracted from media-player-state: app=\(appId ?? "nil"), state=\(state ?? "nil"), pos=\(position?.description ?? "nil"), dur=\(duration?.description ?? "nil"), title=\(title ?? "nil")"
      )

      // Return with state, app ID, position, duration, and title
      return .mediaPlayerStateChanged(
        state ?? "unknown", appId: appId, position: position, duration: duration, title: title)

    default:
      // Log unknown notification types with full JSON for analysis
      Log.info("RokuWS", "🔍 Unknown notification type '\(notifyType)': \(json)")
      return .other(notifyType, [:])
    }

    return nil
  }

  // MARK: - Commands

  /// Send a keypress command
  func sendKeypress(_ key: String) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    DebugBuild.run {
      Log.debug(
        "RokuWS",
        "➡️ key-press key=\(key) requestId=\(requestId) device=\(deviceName) ip=\(deviceIP)"
      )
    }

    // Build keypress JSON - note: uses "param-key" not just "key"
    let keypressJSON = """
      {"request":"key-press","param-key":"\(key)","request-id":"\(requestId)"}
      """

    let response = try await sendRequestWithTimeout(
      keypressJSON, to: conn, requestId: requestId, timeout: 5)

    // 200 = OK, 202 = Accepted (busy but will process)
    DebugBuild.run {
      Log.debug(
        "RokuWS",
        "⬅️ key-press ack key=\(key) requestId=\(requestId) status=\(response.status) msg=\(response.statusMsg ?? "nil")"
      )
    }
    guard response.status == "200" || response.status == "202" else {
      throw ECPError.sendFailed("Keypress \(key) failed: \(response.status)")
    }
  }

  /// Query installed apps via WebSocket (bypasses HTTP 403)
  func queryApps() async throws -> Data? {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let queryJSON = """
      {"request":"query-apps","request-id":"\(requestId)"}
      """

    Log.debug("RokuWS", "📡 Querying apps via WebSocket...")

    let response = try await sendRequestWithTimeout(
      queryJSON, to: conn, requestId: requestId, timeout: 10)

    guard response.isSuccess else {
      Log.error(
        "RokuWS", "query-apps failed: \(response.status) - \(response.statusMsg ?? "unknown")")
      throw ECPError.sendFailed("query-apps failed: \(response.status)")
    }

    Log.debug("RokuWS", "query-apps succeeded, contentType: \(response.contentType ?? "none")")
    return response.decodedContentData
  }

  /// Query app icon via WebSocket
  func queryAppIcon(appId: String) async throws -> Data? {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let queryJSON = """
      {"request":"query-icon","request-id":"\(requestId)","param-channel-id":"\(appId)"}
      """

    let response = try await sendRequestWithTimeout(
      queryJSON, to: conn, requestId: requestId, timeout: 10)

    guard response.isSuccess else {
      return nil
    }

    return response.decodedContentData
  }

  /// Launch an app via WebSocket
  func launchApp(appId: String) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let launchJSON = """
      {"request":"launch","request-id":"\(requestId)","param-channel-id":"\(appId)"}
      """

    let response = try await sendRequestWithTimeout(
      launchJSON, to: conn, requestId: requestId, timeout: 5)

    guard response.isSuccess else {
      throw ECPError.sendFailed("launch failed: \(response.status)")
    }
  }

  // MARK: - Additional ECP-2 Commands (Stubs for Future Use)

  /// Query currently active app
  func queryActiveApp() async throws -> Data? {
    try await sendQuery(request: "query-active-app")
  }

  /// Query device info via WebSocket (alternative to HTTP)
  func queryDeviceInfo() async throws -> Data? {
    try await sendQuery(request: "query-device-info")
  }

  /// Query audio device capabilities (for private listening)
  func queryAudioDevice() async throws -> Data? {
    try await sendQuery(request: "query-audio-device")
  }

  /// Query text edit state (for keyboard input scenarios)
  func queryTexteditState() async throws -> Data? {
    try await sendQuery(request: "query-textedit-state")
  }

  /// Query media player state (position, duration, play/pause)
  func queryMediaPlayer() async throws -> Data? {
    try await sendQuery(request: "query-media-player")
  }

  /// Set text in a text edit field (for keyboard input)
  func setTexteditText(texteditId: String, text: String) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    // Escape text for JSON
    let escapedText = text.replacingOccurrences(of: "\"", with: "\\\"")
    let json = """
      {"request":"set-textedit-text","request-id":"\(requestId)","param-textedit-id":"\(texteditId)","param-text":"\(escapedText)"}
      """

    let response = try await sendRequestWithTimeout(
      json, to: conn, requestId: requestId, timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("set-textedit-text failed: \(response.status)")
    }
  }

  /// Set audio output mode (for private listening / headphones)
  /// - Parameters:
  ///   - output: "datagram" for streaming, "default" for TV speakers
  ///   - devname: For datagram mode: "hostIP:port:payloadType:packetSize"
  func setAudioOutput(output: String, devname: String? = nil) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    var json: String
    if let devname = devname {
      json = """
        {"request":"set-audio-output","request-id":"\(requestId)","param-audio-output":"\(output)","param-devname":"\(devname)"}
        """
    } else {
      json = """
        {"request":"set-audio-output","request-id":"\(requestId)","param-audio-output":"\(output)"}
        """
    }

    let response = try await sendRequestWithTimeout(
      json, to: conn, requestId: requestId, timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("set-audio-output failed: \(response.status)")
    }
  }

  /// Query voice service info (for voice control features)
  func queryVoiceServiceInfo() async throws -> Data? {
    try await sendQuery(request: "query-info-for-voice-service")
  }

  /// Send voice events (for voice control - requires additional setup)
  func sendVoiceEvents(sessionId: String, events: String) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let json = """
      {"request":"send-voice-events","request-id":"\(requestId)","param-session-id":"\(sessionId)","param-events":"\(events)"}
      """

    let response = try await sendRequestWithTimeout(
      json, to: conn, requestId: requestId, timeout: 10)
    guard response.isSuccess else {
      throw ECPError.sendFailed("send-voice-events failed: \(response.status)")
    }
  }

  // MARK: - Helper for Simple Queries

  /// Send a raw JSON command and get the response (for Protocol Explorer)
  func sendRawCommand(_ json: String) async throws -> Data? {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    // Extract request-id from the JSON if present, or generate one
    let requestId: String
    if let data = json.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = parsed["request-id"] as? String
    {
      requestId = id
    } else {
      requestId = "explorer-\(Int.random(in: 1000...9999))"
    }

    let response = try await sendRequestWithTimeout(
      json, to: conn, requestId: requestId, timeout: 10)
    return response.decodedContentData
  }

  /// Send a raw JSON command without waiting for response (fire-and-forget for explorer)
  func sendRawFireAndForget(
    _ json: String,
    responseHandler: @escaping @MainActor (String) -> Void
  ) async throws {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    // Extract request-id to match responses
    let requestId: String
    if let data = json.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = parsed["request-id"] as? String
    {
      requestId = id
    } else {
      requestId = ""
    }

    // Register handler for this request's responses
    if !requestId.isEmpty {
      explorerResponseHandlers[requestId] = responseHandler
    }

    // Send without waiting
    try await sendWebSocketMessage(json, to: conn)
  }

  /// Response handlers for explorer fire-and-forget commands
  private var explorerResponseHandlers: [String: @MainActor (String) -> Void] = [:]

  /// Called when a response comes in - check if explorer is waiting for it
  func handleExplorerResponse(_ requestId: String, _ response: String) {
    if let handler = explorerResponseHandlers.removeValue(forKey: requestId) {
      Task { @MainActor in
        handler(response)
      }
    }
  }

  private func sendQuery(request: String) async throws -> Data? {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let json = """
      {"request":"\(request)","request-id":"\(requestId)"}
      """

    let response = try await sendRequestWithTimeout(
      json, to: conn, requestId: requestId, timeout: 10)

    guard response.isSuccess else {
      throw ECPError.sendFailed("\(request) failed: \(response.status)")
    }

    return response.decodedContentData
  }

  // MARK: - Unverified helpers (experimental; best guesses only)

  private func jsonEscaped(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\t", with: "\\t")
  }

  private func unverifiedRequestJSON(request: String, requestId: String, params: [String: String])
    -> String
  {
    if params.isEmpty {
      return """
        {"request":"\(request)","request-id":"\(requestId)"}
        """
    }

    let paramJSON =
      params
      .sorted(by: { $0.key < $1.key })
      .map { key, value in
        "\"\(jsonEscaped(key))\":\"\(jsonEscaped(value))\""
      }
      .joined(separator: ",")

    return """
      {"request":"\(request)","request-id":"\(requestId)",\(paramJSON)}
      """
  }

  private func sendUnverifiedRequest(
    request: String,
    params: [String: String] = [:],
    timeout: UInt64 = 10
  ) async throws -> ECPResponseMsg {
    guard state == .connected, let conn = connection else {
      throw ECPError.notConnected
    }

    let requestId = String(requestCounter)
    requestCounter += 1

    let json = unverifiedRequestJSON(request: request, requestId: requestId, params: params)
    return try await sendRequestWithTimeout(json, to: conn, requestId: requestId, timeout: timeout)
  }

  /// Best-guess ECP-2 mapping for ECP-1 POST /install/<channel-id>
  func UnverifiedInstall(channelId: String, contentId: String? = nil, mediaType: String? = nil)
    async throws
  {
    var params: [String: String] = ["param-channel-id": channelId]
    if let contentId, !contentId.isEmpty { params["param-contentid"] = contentId }
    if let mediaType, !mediaType.isEmpty { params["param-mediatype"] = mediaType }

    let response = try await sendUnverifiedRequest(request: "install", params: params, timeout: 10)
    guard response.isSuccess else {
      throw ECPError.sendFailed("install failed: \(response.status)")
    }
  }

  /// Roku TV only - best-guess ECP-2 mapping for ECP-1 GET /query/tv-channels
  func UnverifiedQueryTVChannels() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-tv-channels", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  /// Roku TV only - best-guess ECP-2 mapping for ECP-1 GET /query/tv-active-channel
  func UnverifiedQueryTVActiveChannel() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-tv-active-channel", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  /// Roku TV only - best-guess ECP-2 mapping for ECP-1 POST /launch/tvinput.dtv?ch=...
  func UnverifiedLaunchTVTuner(ch: String? = nil) async throws {
    var params: [String: String] = ["param-channel-id": "tvinput.dtv"]
    if let ch, !ch.isEmpty { params["param-ch"] = ch }

    let response = try await sendUnverifiedRequest(request: "launch", params: params, timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("launch tvinput.dtv failed: \(response.status)")
    }
  }

  /// Best-guess ECP-2 mapping for ECP-1 POST /input?<query>
  func UnverifiedInput(queryString: String) async throws {
    let response = try await sendUnverifiedRequest(
      request: "input",
      params: ["param-query-string": queryString],
      timeout: 5
    )
    guard response.isSuccess else {
      throw ECPError.sendFailed("input failed: \(response.status)")
    }
  }

  /// Best-guess ECP-2 mapping for ECP-1 POST /search?<query>
  func UnverifiedSearch(queryString: String) async throws {
    let response = try await sendUnverifiedRequest(
      request: "search",
      params: ["param-query-string": queryString],
      timeout: 10
    )
    guard response.isSuccess else {
      throw ECPError.sendFailed("search failed: \(response.status)")
    }
  }

  // MARK: - UnverifiedDeveloper helpers (experimental; best guesses only)

  func UnverifiedDeveloperQueryR2D2Bitmaps() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-r2d2-bitmaps", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQueryGraphicsFrameRate() async throws -> Data? {
    let response = try await sendUnverifiedRequest(
      request: "query-graphics-frame-rate", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQueryFWBeacons() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-fwbeacons", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperFWBeaconsTrack(channelId: String? = nil) async throws {
    var params: [String: String] = [:]
    if let channelId, !channelId.isEmpty { params["param-channel-id"] = channelId }

    let response = try await sendUnverifiedRequest(
      request: "fwbeacons-track", params: params, timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("fwbeacons-track failed: \(response.status)")
    }
  }

  func UnverifiedDeveloperFWBeaconsUntrack() async throws {
    let response = try await sendUnverifiedRequest(request: "fwbeacons-untrack", timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("fwbeacons-untrack failed: \(response.status)")
    }
  }

  func UnverifiedDeveloperQuerySGNodesAll() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-sgnodes-all", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQuerySGNodesRoots() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-sgnodes-roots", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQuerySGNodesNode(nodeId: String) async throws -> Data? {
    let response = try await sendUnverifiedRequest(
      request: "query-sgnodes-nodes",
      params: ["param-node-id": nodeId],
      timeout: 10
    )
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQueryChanPerf() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-chanperf", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQueryChanPerfForChannel(channelId: String, durationSeconds: Int? = nil)
    async throws -> Data?
  {
    var params: [String: String] = ["param-channel-id": channelId]
    if let durationSeconds { params["param-duration-seconds"] = String(durationSeconds) }

    let response = try await sendUnverifiedRequest(
      request: "query-chanperf-channel", params: params, timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQueryRegistry(
    channelId: String,
    keys: String? = nil,
    sections: String? = nil,
    escaped: Bool? = nil
  ) async throws -> Data? {
    var params: [String: String] = ["param-channel-id": channelId]
    if let keys, !keys.isEmpty { params["param-keys"] = keys }
    if let sections, !sections.isEmpty { params["param-sections"] = sections }
    if let escaped { params["param-escaped"] = escaped ? "true" : "false" }

    let response = try await sendUnverifiedRequest(
      request: "query-registry", params: params, timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperQuerySGRendezvous() async throws -> Data? {
    let response = try await sendUnverifiedRequest(request: "query-sgrendezvous", timeout: 10)
    guard response.isSuccess else { return nil }
    return response.decodedContentData
  }

  func UnverifiedDeveloperSGRendezvousTrack() async throws {
    let response = try await sendUnverifiedRequest(request: "sgrendezvous-track", timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("sgrendezvous-track failed: \(response.status)")
    }
  }

  func UnverifiedDeveloperSGRendezvousUntrack() async throws {
    let response = try await sendUnverifiedRequest(request: "sgrendezvous-untrack", timeout: 5)
    guard response.isSuccess else {
      throw ECPError.sendFailed("sgrendezvous-untrack failed: \(response.status)")
    }
  }

  private func sendRequestWithTimeout(
    _ json: String,
    to conn: NWConnection,
    requestId: String,
    timeout: UInt64
  ) async throws -> ECPResponseMsg {
    try await withCheckedThrowingContinuation { continuation in
      Task { [weak self] in
        guard let self else {
          continuation.resume(throwing: ECPError.connectionFailed("Client deallocated"))
          return
        }

        // Register continuation before sending so we can receive the response.
        await self.registerPendingResponse(id: requestId, continuation: continuation)

        // Timeout task: best-effort (no-ops if the response already completed).
        let t = Task { [weak self] in
          guard let self else { return }
          do {
            try await Task.sleep(nanoseconds: timeout * 1_000_000_000)
          } catch {
            return
          }
          await self.finishPendingResponse(id: requestId, result: .failure(ECPError.timeout))
        }
        await self.storePendingResponseTimeoutTask(t, for: requestId)

        do {
          try await self.sendWebSocketMessage(json, to: conn)
        } catch {
          await self.finishPendingResponse(id: requestId,   result: .failure(error))
        }
      }
    }
  }

  private func registerPendingResponse(
    id: String,
    continuation: CheckedContinuation<ECPResponseMsg, Error>
  ) {
    pendingResponses[id] = continuation
  }

  private func storePendingResponseTimeoutTask(_ task: Task<Void, Never>, for id: String) {
    pendingResponseTimeoutTasks[id] = task
  }

  private func finishPendingResponse(id: String, result: Result<ECPResponseMsg, Error>) {
    // Cancel any outstanding timeout task.
    if let t = pendingResponseTimeoutTasks.removeValue(forKey: id) {
      t.cancel()
    }

    guard let continuation = pendingResponses.removeValue(forKey: id) else { return }
    continuation.resume(with: result)
  }

  private func failAllPendingResponses(with error: Error) {
    // Cancel timeouts first (prevents later task wakeups doing extra actor work).
    for (_, t) in pendingResponseTimeoutTasks {
      t.cancel()
    }
    pendingResponseTimeoutTasks.removeAll()

    let continuations = pendingResponses.values
    pendingResponses.removeAll()
    for c in continuations {
      c.resume(throwing: error)
    }
  }

}

// MARK: - State Helper

extension RokuWebSocketClient.ConnectionState {
  nonisolated var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }
}

// MARK: - Message Types (Sendable for actor use)

private struct AuthChallenge: Decodable, Sendable {
  let notify: String
  let paramChallenge: String
  let timestamp: String?

  enum CodingKeys: String, CodingKey {
    case notify
    case paramChallenge = "param-challenge"
    case timestamp
  }
}

struct ECPResponseMsg: Decodable, Sendable {
  let response: String
  let responseId: String
  let status: String
  let statusMsg: String?
  let contentData: String?  // Base64-encoded data for query responses
  let contentType: String?

  enum CodingKeys: String, CodingKey {
    case response
    case responseId = "response-id"
    case status
    case statusMsg = "status-msg"
    case contentData = "content-data"
    case contentType = "content-type"
  }

  /// "Success" varies by command:
  /// - 200: OK
  /// - 202: Accepted (device busy, will process)
  /// - 204: No Content (observed for some `launch` responses; still indicates success)
  var isSuccess: Bool { status == "200" || status == "202" || status == "204" }

  /// Decode base64 content data
  var decodedContentData: Data? {
    guard let contentData else { return nil }
    return Data(base64Encoded: contentData)
  }
}
