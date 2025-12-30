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

  public init() {}
}
