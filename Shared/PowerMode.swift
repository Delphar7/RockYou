//
//  PowerMode.swift
//  RockYou (Shared)
//
//  Device power state - shared between Phone and Watch.
//

import SwiftUI

/// Roku device power state
public enum PowerMode: String, Codable, Sendable {
  case on = "power-on"
  case off = "power-off"
  case displayOff = "display-off"
  case ready = "ready"
  case unknown = "unknown"

  /// Parse Roku ECP `/query/device-info` `power-mode` strings.
  /// If the value is missing or unrecognized, this returns `.on` (device responded).
  public static func fromECPPowerMode(_ value: String?) -> PowerMode {
    guard let value = value?.lowercased() else { return .on }
    switch value {
    case "poweron", "power-on":
      return .on
    case "ready":
      return .ready
    case "poweroff", "power-off":
      return .off
    case "displayoff", "display-off":
      return .displayOff
    default:
      return .on
    }
  }

  /// Whether the device screen is actually on.
  /// - `on` = TV is on, screen showing content
  /// - `ready` = Roku standby mode (screen dark, essentially "off" for user)
  /// - `displayOff` = screen off but still streaming audio
  /// - `off` = fully powered off
  /// - `unknown` = assume on to avoid accidental "turn on" when already on
  public var isOn: Bool {
    switch self {
    case .on: return true                    // Actually on
    case .unknown: return true               // Assume on until proven off
    case .ready, .off, .displayOff: return false  // All "off" states
    }
  }

  /// Status dot color for UI
  public var statusColor: Color {
    switch self {
    case .on:
      return powerButtonDarkGreen
    case .ready:
      return .orange
    case .off, .displayOff:
      return .red
    case .unknown:
      return .orange
    }
  }
}
