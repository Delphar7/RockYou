//
//  DeviceState.swift
//  RockYou (Shared)
//
//  Observable device state - shared between Phone and Watch.
//  Phone updates this from ECP-2, Watch receives via WatchConnectivity.
//

import Foundation

// MARK: - Device Type

/// Type of Roku device
public enum RokuDeviceType: String, Codable, Sendable {
  case tv = "TV"
  case streamingDevice = "Streaming Device"
}

/// Device state that can be synced between Phone and Watch
public struct DeviceState: Codable, Equatable, Sendable {
  public var powerMode: PowerMode = .unknown
  public var volume: Int = 0
  public var muted: Bool = false
  public var mediaState: MediaState = .idle
  public var activeApp: String? = nil
  public var mediaPosition: Int? = nil  // Position in milliseconds
  public var mediaDuration: Int? = nil  // Total duration in milliseconds
  public var isLive: Bool? = nil
  public var isLiveBlocked: Bool? = nil

  public enum MediaState: String, Codable, Sendable {
    case play = "play"
    case pause = "pause"
    case stop = "stop"
    case idle = "none"
  }

  /// Create from dictionary (for WatchConnectivity messages)
  public init(from dict: [String: Any]) {
    if let pm = dict["powerMode"] as? String {
      self.powerMode = PowerMode(rawValue: pm) ?? .unknown
    }
    if let vol = dict["volume"] as? Int {
      self.volume = vol
    }
    if let m = dict["muted"] as? Bool {
      self.muted = m
    }
    if let ms = dict["mediaState"] as? String {
      self.mediaState = MediaState(rawValue: ms) ?? .idle
    }
    self.activeApp = dict["activeApp"] as? String
    if let pos = dict["mediaPosition"] as? Int {
      self.mediaPosition = pos
    }
    if let dur = dict["mediaDuration"] as? Int {
      self.mediaDuration = dur
    }
    if let live = dict["isLive"] as? Bool {
      self.isLive = live
    }
    if let blocked = dict["isLiveBlocked"] as? Bool {
      self.isLiveBlocked = blocked
    }
  }

  public init() {}

  /// Convert to dictionary for WatchConnectivity messages
  public func toDictionary() -> [String: Any] {
    var dict: [String: Any] = [
      "powerMode": powerMode.rawValue,
      "volume": volume,
      "muted": muted,
      "mediaState": mediaState.rawValue
    ]
    if let app = activeApp {
      dict["activeApp"] = app
    }
    if let pos = mediaPosition {
      dict["mediaPosition"] = pos
    }
    if let dur = mediaDuration {
      dict["mediaDuration"] = dur
    }
    if let isLive {
      dict["isLive"] = isLive
    }
    if let isLiveBlocked {
      dict["isLiveBlocked"] = isLiveBlocked
    }
    return dict
  }
}
