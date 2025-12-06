//
//  DeviceStateProviding.swift
//  RockYou (Shared)
//
//  Protocol for accessing device state across platforms.
//  iPhone gets state from ECP/WebSocket, Watch gets it from iPhone.
//
//  Usage:
//    let powerMode = stateProvider.powerMode(for: deviceId)
//

import SwiftUI
import Combine

// MARK: - Protocol

/// Abstraction for accessing device state across platforms.
/// Platform-specific implementations manage their own data sources.
/// Note: Individual implementations may be @MainActor, but the protocol itself doesn't require it.
protocol DeviceStateProviding: AnyObject {
  /// The currently selected device identifier (IP on iOS, device ID on Watch)
  var selectedDeviceId: String? { get }

  /// Get current power mode for a device
  func powerMode(for deviceId: String) -> PowerMode

  /// Get full device state for a device
  func deviceState(for deviceId: String) -> DeviceState
}

// MARK: - Default Implementation

extension DeviceStateProviding {
  /// Convenience: power mode for currently selected device
  var currentPowerMode: PowerMode {
    guard let id = selectedDeviceId else { return .unknown }
    return powerMode(for: id)
  }

  /// Convenience: full state for currently selected device
  var currentDeviceState: DeviceState {
    guard let id = selectedDeviceId else { return DeviceState() }
    return deviceState(for: id)
  }
}

// MARK: - Platform-Specific Provider Access

/// Shared accessor for the platform-specific device state provider
/// Use this instead of platform conditionals to get the selected device ID
/// Note: Marked @MainActor because it accesses @MainActor classes
// Implemented in `DeviceSelectionProvider+watchOS.swift` and `DeviceSelectionProvider+nonWatch.swift`
// to avoid `#if` branching in shared code.
