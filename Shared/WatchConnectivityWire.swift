//
//  WatchConnectivityWire.swift
//  RockYou (Shared)
//
//  Typed WatchConnectivity message schema shared between iPhone and Watch.
//

import Foundation

public enum WCWireMessage: Codable, Sendable, Equatable {
  case request(WCRequest)
  case reply(WCReply)
  case event(WCEvent)
}

public enum WCRequest: Codable, Sendable, Equatable {
  case handshake
  case requestDevices

  case keypress(deviceId: String?, deviceIdx: String?, key: String)
  case requestApps(deviceId: String)
  case launchApp(deviceId: String?, deviceIdx: String?, appId: String)

  case requestIcon(WCIconRequest)
  case requestIconsBatch(WCIconsBatchRequest)
}

public enum WCReply: Codable, Sendable, Equatable {
  case ok
  case throttled
  case error(String)

  case handshake(WCHandshakeReply)
  case appsAck(count: Int)
  case iconsBatchAck(sent: Int, unchanged: Int)
  case iconStatus(WCIconReplyStatus)
}

public enum WCEvent: Codable, Sendable, Equatable {
  case deviceList(WCDeviceListEvent)
  case appList(WCAppListEvent)
  case deviceState(deviceId: String, state: DeviceState)
  case mruUpdate(deviceId: String, mru: [String: TimeInterval])
}

public struct WCSyncedSettings: Codable, Sendable, Equatable {
  public var watchPowerDelay: TimeInterval
  public var watchHomeDelay: TimeInterval
  public var watchAppLaunchDelay: TimeInterval
  public var watchLaunchScreen: String
  public var watchAlwaysLaunchToMedia: Bool

  public init(
    watchPowerDelay: TimeInterval,
    watchHomeDelay: TimeInterval,
    watchAppLaunchDelay: TimeInterval,
    watchLaunchScreen: String,
    watchAlwaysLaunchToMedia: Bool
  ) {
    self.watchPowerDelay = watchPowerDelay
    self.watchHomeDelay = watchHomeDelay
    self.watchAppLaunchDelay = watchAppLaunchDelay
    self.watchLaunchScreen = watchLaunchScreen
    self.watchAlwaysLaunchToMedia = watchAlwaysLaunchToMedia
  }
}

public struct WCHandshakeReply: Codable, Sendable, Equatable {
  public var devices: [DeviceInfo]
  public var settings: WCSyncedSettings

  public init(devices: [DeviceInfo], settings: WCSyncedSettings) {
    self.devices = devices
    self.settings = settings
  }
}

public struct WCDeviceListEvent: Codable, Sendable, Equatable {
  public var devices: [DeviceInfo]
  public var settings: WCSyncedSettings?

  public init(devices: [DeviceInfo], settings: WCSyncedSettings?) {
    self.devices = devices
    self.settings = settings
  }
}

public struct WCAppListEvent: Codable, Sendable, Equatable {
  public var deviceId: String
  public var apps: [RokuApp]
  public var mru: [String: TimeInterval]

  public init(deviceId: String, apps: [RokuApp], mru: [String: TimeInterval]) {
    self.deviceId = deviceId
    self.apps = apps
    self.mru = mru
  }
}

public struct WCIconHash: Codable, Sendable, Equatable, Hashable {
  public var appId: String
  public var hash: String

  public init(appId: String, hash: String) {
    self.appId = appId
    self.hash = hash
  }
}

public struct WCIconRequest: Codable, Sendable, Equatable {
  public var deviceId: String
  public var appId: String
  public var hash: String

  public init(deviceId: String, appId: String, hash: String) {
    self.deviceId = deviceId
    self.appId = appId
    self.hash = hash
  }
}

public struct WCIconsBatchRequest: Codable, Sendable, Equatable {
  public var deviceId: String
  public var ordered: [WCIconHash]

  public init(deviceId: String, ordered: [WCIconHash]) {
    self.deviceId = deviceId
    self.ordered = ordered
  }
}

public enum WCIconReplyStatus: String, Codable, Sendable {
  case sent
  case unchanged
  case notFound
}

public struct WCApplicationContext: Codable, Sendable, Equatable {
  public static let key = "wcContext.v1"

  public var snapshot: WatchSurfaceSnapshot
  public var settings: WCSyncedSettings

  public init(snapshot: WatchSurfaceSnapshot, settings: WCSyncedSettings) {
    self.snapshot = snapshot
    self.settings = settings
  }
}

public enum WCWireCodec {
  public static func encode(_ message: WCWireMessage) throws -> Data {
    try JSONEncoder().encode(message)
  }

  public static func decode(_ data: Data) throws -> WCWireMessage {
    try JSONDecoder().decode(WCWireMessage.self, from: data)
  }

  public static func isLikelyJSONMessage(_ data: Data) -> Bool {
    guard let first = data.first else { return false }
    return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
  }
}
