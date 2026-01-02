//
//  DeviceInfo.swift
//  RockYou (Shared)
//
//  Unified device info struct used by both iOS and watchOS.
//  Unified struct replacing previous platform-specific types.
//

import Foundation

/// Unified Roku device information - shared across all platforms
public struct DeviceInfo: Codable, Identifiable, Hashable, Sendable {
  // MARK: - Core Fields (required on all platforms)

  public let id: String           // Serial number or unique device ID
  public let name: String         // User device name or friendly name
  public let location: String?    // User device location (room name)
  public var ipAddress: String    // IP address (may change via DHCP)
  public let isTV: Bool           // true = Roku TV, false = streaming device

  // MARK: - iOS-Specific Fields (optional, unused on watchOS)

  public var model: String?       // Model name (e.g., "Roku Ultra")
  public var port: Int            // ECP port (default 8060)
  public var lastSeen: Date?      // For cache staleness tracking

  // MARK: - Debug / Capability Bag (iOS + macOS; watchOS typically doesn't populate this)

  /// Raw tag->value mapping from `/query/device-info`.
  /// Intended for internal debugging and lightweight capability checks.
  public var properties: [String: String]

  // MARK: - watchOS-Specific Fields (optional, unused on iOS)

  public var idx: String?         // Message routing index for Watch↔iPhone

  // MARK: - Computed Properties

  /// Device type enum (derived from isTV)
  public var deviceType: RokuDeviceType {
    isTV ? .tv : .streamingDevice
  }

  public var isStreamingDevice: Bool { !isTV }

  /// ECP base URL for network calls
  public var ecpBaseURL: URL? {
    URL(string: "http://\(ipAddress):\(port)")
  }

  /// Device is "stale" if it hasn't been seen recently (used to show power-off state in UI).
  public var isStale: Bool {
    guard let lastSeen else { return true }
    return lastSeen < Date().addingTimeInterval(-5 * 60)
  }

  /// Device is "orphaned" if it hasn't been seen in a long time (used to purge from cache).
  public var isOrphaned: Bool {
    guard let lastSeen else { return false }
    return lastSeen < Date().addingTimeInterval(-72 * 60 * 60)
  }

  // MARK: - Initializers

  /// Full initializer with all fields
  public init(
    id: String,
    name: String,
    location: String? = nil,
    ipAddress: String,
    isTV: Bool,
    model: String? = nil,
    properties: [String: String] = [:],
    port: Int = 8060,
    lastSeen: Date? = nil,
    idx: String? = nil
  ) {
    self.id = id
    self.name = name
    self.location = location
    self.ipAddress = ipAddress
    self.isTV = isTV
    self.model = model
    self.properties = properties
    self.port = port
    self.lastSeen = lastSeen
    self.idx = idx
  }

  /// Update with fresh discovery data (IP may have changed)
  public func updated(ipAddress: String, name: String? = nil, location: String? = nil) -> DeviceInfo {
    DeviceInfo(
      id: self.id,
      name: name ?? self.name,
      location: location ?? self.location,
      ipAddress: ipAddress,
      isTV: self.isTV,
      model: self.model,
      properties: self.properties,
      port: self.port,
      lastSeen: Date(),
      idx: self.idx
    )
  }

  // MARK: - Capability helpers

  /// Returns true if `supports-<capability>` exists and is truthy in `properties`.
  ///
  /// - Examples:
  ///   - `supports("rva")` checks `supports-rva`
  ///   - `supports("supports-ecs-textedit")` checks `supports-ecs-textedit`
  ///
  /// Notes:
  /// - Many Roku fields only appear when true; absence is treated as false.
  /// - If the tag exists but has an empty value, we treat it as true (presence-only boolean).
  public func supports(_ capability: String) -> Bool {
    let key: String = {
      if capability.hasPrefix("supports-") { return capability }
      return "supports-\(capability)"
    }()

    guard let raw = properties[key] else { return false }
    let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if v.isEmpty { return true }
    return v == "true" || v == "1" || v == "yes"
  }

  // MARK: - Hashable (by id only for stable collections)

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  public static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
    lhs.id == rhs.id
  }

  // MARK: - Codable (backward-compatible)

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case location
    case ipAddress
    case isTV
    case model
    case port
    case lastSeen
    case properties
    case idx
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    location = try c.decodeIfPresent(String.self, forKey: .location)
    ipAddress = try c.decode(String.self, forKey: .ipAddress)
    isTV = try c.decode(Bool.self, forKey: .isTV)
    model = try c.decodeIfPresent(String.self, forKey: .model)
    port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 8060
    lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
    properties = try c.decodeIfPresent([String: String].self, forKey: .properties) ?? [:]
    idx = try c.decodeIfPresent(String.self, forKey: .idx)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encodeIfPresent(location, forKey: .location)
    try c.encode(ipAddress, forKey: .ipAddress)
    try c.encode(isTV, forKey: .isTV)
    try c.encodeIfPresent(model, forKey: .model)
    try c.encode(port, forKey: .port)
    try c.encodeIfPresent(lastSeen, forKey: .lastSeen)
    if !properties.isEmpty {
      try c.encode(properties, forKey: .properties)
    }
    try c.encodeIfPresent(idx, forKey: .idx)
  }
}
