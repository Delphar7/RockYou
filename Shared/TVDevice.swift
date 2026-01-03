//
//  TVDevice.swift
//  RockYou (Shared)
//
//  Shared abstractions for "general purpose TV devices".
//
//  RockYou started as a Roku-focused app, but as we expand to other TV ecosystems
//  we need a shared vocabulary for discovery, capabilities, and control providers.
//

import Foundation

/// Tri-state support indicator for a device capability.
///
/// Many protocols only report capabilities when `true`, and absence of a field is not a reliable `false`.
public enum TVCapabilitySupport: String, Codable, Sendable, CaseIterable {
  case yes
  case no
  case unknown

  public var isYes: Bool { self == .yes }
  public var isNo: Bool { self == .no }
}

/// Broad category for a controllable device.
///
/// Note: A "TV" here is the panel (power/volume), while a "streamer" is a playback/navigation box.
public enum TVDeviceKind: String, Codable, Sendable, CaseIterable {
  case tv
  case streamer
  case unknown
}

/// The control protocol family we believe a device speaks.
///
/// This is intentionally high-level; concrete clients live elsewhere.
public enum TVControlProtocolKind: String, Codable, Sendable, CaseIterable {
  case rokuECP
  case lgWebOSSSAP
  case samsungTizenWS
  case sonyBraviaIRCC
  case unknown
}

