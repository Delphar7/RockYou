//
//  WatchComplicationTargetPicker.swift
//  RockYou (Shared)
//

import Foundation

public enum WatchComplicationIconHint: Codable, Equatable, Sendable {
  /// Render as the active channel's icon if available.
  case channel(appId: String)
  /// Render as a generic "Roku TV" icon (app-brand mark + status dot).
  case rokuDevice
}

public struct WatchComplicationTarget: Codable, Equatable, Sendable {
  public enum Priority: Int, Codable, Equatable, Sendable {
    case singleOnWithActiveApp = 1
    case singleOn = 2
    case lastActive = 3
    case firstAvailable = 4
  }

  public let deviceId: String
  public let deviceName: String
  public let powerMode: PowerMode
  public let activeAppId: String?
  public let iconHint: WatchComplicationIconHint
  public let priority: Priority
}

/// Deterministic target picking logic for watch complications/widgets.
///
/// Priority rules:
/// 1. If exactly one device is "on" *and* has an active app, pick it.
/// 2. Else, if exactly one device is "on", pick it.
/// 3. Else, if `lastActiveDeviceId` exists in the snapshot, pick it.
/// 4. Else, pick the first device in the snapshot (stable, deterministic).
public enum WatchComplicationTargetPicker {

  public static func pick(
    snapshot: WatchSurfaceSnapshot,
    lastActiveDeviceId: String?
  ) -> WatchComplicationTarget? {
    guard !snapshot.devices.isEmpty else { return nil }

    func state(for deviceId: String) -> DeviceState {
      snapshot.deviceStates[deviceId] ?? DeviceState()
    }

    let onAndActiveApp: [DeviceInfo] = snapshot.devices.filter { device in
      let s = state(for: device.id)
      return s.powerMode.isOn && (s.activeApp?.isEmpty == false)
    }
    if onAndActiveApp.count == 1, let d = onAndActiveApp.first {
      let s = state(for: d.id)
      let appId = s.activeApp ?? ""
      return WatchComplicationTarget(
        deviceId: d.id,
        deviceName: d.name,
        powerMode: s.powerMode,
        activeAppId: s.activeApp,
        iconHint: .channel(appId: appId),
        priority: .singleOnWithActiveApp
      )
    }

    let onDevices: [DeviceInfo] = snapshot.devices.filter { device in
      state(for: device.id).powerMode.isOn
    }
    if onDevices.count == 1, let d = onDevices.first {
      let s = state(for: d.id)
      return WatchComplicationTarget(
        deviceId: d.id,
        deviceName: d.name,
        powerMode: s.powerMode,
        activeAppId: s.activeApp,
        iconHint: .rokuDevice,
        priority: .singleOn
      )
    }

    if let lastActiveDeviceId,
       let d = snapshot.devices.first(where: { $0.id == lastActiveDeviceId }) {
      let s = state(for: d.id)
      return WatchComplicationTarget(
        deviceId: d.id,
        deviceName: d.name,
        powerMode: s.powerMode,
        activeAppId: s.activeApp,
        iconHint: (s.activeApp?.isEmpty == false) ? .channel(appId: s.activeApp!) : .rokuDevice,
        priority: .lastActive
      )
    }

    let first = snapshot.devices[0]
    let s = state(for: first.id)
    return WatchComplicationTarget(
      deviceId: first.id,
      deviceName: first.name,
      powerMode: s.powerMode,
      activeAppId: s.activeApp,
      iconHint: (s.activeApp?.isEmpty == false) ? .channel(appId: s.activeApp!) : .rokuDevice,
      priority: .firstAvailable
    )
  }
}
