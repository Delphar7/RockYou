//
//  DeviceStateManager.swift
//  RockYou (Shared)
//
//  Unified device state manager for all platforms.
//  Replaces RokuDeviceStates (iOS) and WatchDeviceStates (watchOS).
//  Keys by device ID (stable) not IP (can change with DHCP).
//

import Foundation

/// Unified device state manager - observable for SwiftUI
@Observable
@MainActor
public final class DeviceStateManager {
  public static let shared = DeviceStateManager()

  // MARK: - State Storage

  /// Device states keyed by device ID
  public private(set) var states: [String: DeviceState] = [:]

  /// Devices currently (re)connecting their WebSocket. Transient UI state -- not synced to Watch.
  public private(set) var connectingDeviceIds: Set<String> = []

  // MARK: - Change Notification (for non-SwiftUI observers like WatchConnectivity)

  public typealias StateChangedHandler =
    @MainActor (_ deviceId: String, _ newState: DeviceState) -> Void

  /// Register a state-change handler. Returns a token you can use to remove it.
  @discardableResult
  public func addStateChangedHandler(_ handler: @escaping StateChangedHandler) -> UUID {
    let id = UUID()
    stateChangedHandlers[id] = handler
    return id
  }

  public func removeStateChangedHandler(_ id: UUID) {
    stateChangedHandlers.removeValue(forKey: id)
  }

  private var stateChangedHandlers: [UUID: StateChangedHandler] = [:]

  private init() {}

  // MARK: - Read State

  /// Get state for a device (returns default if not exists)
  public func state(for deviceId: String) -> DeviceState {
    states[deviceId] ?? DeviceState()
  }

  // MARK: - Write State (full replacement)

  /// Update entire state for a device
  public func updateState(_ state: DeviceState, for deviceId: String) {
    let oldState = states[deviceId]
    states[deviceId] = state

    if oldState != state {
      for handler in stateChangedHandlers.values {
        handler(deviceId, state)
      }
    }
  }

  // MARK: - Write State (partial updates)

  /// Update power mode
  public func setPowerMode(_ mode: PowerMode, for deviceId: String) {
    var state = self.state(for: deviceId)
    guard state.powerMode != mode else { return }
    state.powerMode = mode
    updateState(state, for: deviceId)
  }

  /// Update volume and mute
  public func setVolume(_ volume: Int, muted: Bool, for deviceId: String) {
    var state = self.state(for: deviceId)
    guard state.volume != volume || state.muted != muted else { return }
    state.volume = volume
    state.muted = muted
    updateState(state, for: deviceId)
  }

  /// Update media state
  public func setMediaState(_ mediaState: DeviceState.MediaState, for deviceId: String) {
    var state = self.state(for: deviceId)
    guard state.mediaState != mediaState else { return }
    state.mediaState = mediaState
    updateState(state, for: deviceId)
  }

  /// Update active app
  public func setActiveApp(_ appId: String?, for deviceId: String) {
    var state = self.state(for: deviceId)
    guard state.activeApp != appId else { return }
    state.activeApp = appId
    updateState(state, for: deviceId)
  }

  // MARK: - Connection Phase (transient, not synced)

  public func setConnecting(_ connecting: Bool, for deviceId: String) {
    if connecting { connectingDeviceIds.insert(deviceId) }
    else { connectingDeviceIds.remove(deviceId) }
  }
}
