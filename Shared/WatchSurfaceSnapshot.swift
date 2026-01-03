//
//  WatchSurfaceSnapshot.swift
//  RockYou (Shared)
//

import Foundation

/// A compact, persistent snapshot of the "surface" state needed by watch complications/widgets.
///
/// Notes:
/// - Stored in an App Group (with a safe fallback to standard defaults in local/sandbox builds).
/// - Pushed iPhone → Watch via `WCSession.updateApplicationContext`.
public struct WatchSurfaceSnapshot: Codable, Equatable, Sendable {
  public var generatedAt: TimeInterval
  public var devices: [DeviceInfo]
  /// Optional v2 representation: "whole device" controllers (TV/streamer/paired).
  /// Backward-compatible: older builds ignore unknown keys.
  public var controllers: [DeviceControllerDescriptor]?
  public var deviceStates: [String: DeviceState]

  public init(
    generatedAt: TimeInterval,
    devices: [DeviceInfo],
    controllers: [DeviceControllerDescriptor]? = nil,
    deviceStates: [String: DeviceState]
  ) {
    self.generatedAt = generatedAt
    self.devices = devices
    self.controllers = controllers
    self.deviceStates = deviceStates
  }
}

public enum WatchSurfaceSnapshotStore {
  // If/when we add the App Group entitlement, this should match the configured group.
  public static let appGroupID = "group.com.jtr.RockYou"

  private static let snapshotKey = "watchSurfaceSnapshot.v1"
  private static let lastActiveDeviceIdKey = "watchSurface.lastActiveDeviceId"

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: appGroupID) ?? .standard
  }

  public static func loadSnapshot() -> WatchSurfaceSnapshot? {
    defaults.decoded(forKey: snapshotKey)
  }

  public static func saveSnapshot(_ snapshot: WatchSurfaceSnapshot) {
    defaults.setEncoded(snapshot, forKey: snapshotKey)
  }

  public static var lastActiveDeviceId: String? {
    get { defaults.string(forKey: lastActiveDeviceIdKey) }
    set {
      if let newValue {
        defaults.set(newValue, forKey: lastActiveDeviceIdKey)
      } else {
        defaults.removeObject(forKey: lastActiveDeviceIdKey)
      }
    }
  }
}
