//
//  DeviceControllerDescriptor.swift
//  RockYou (Shared)
//
//  A "whole device" representation that can be:
//  - a single TV endpoint
//  - a single streaming endpoint
//  - a paired TV + streamer, where roles are split (e.g. power/volume on TV, everything else on streamer)
//
//  This type is intentionally:
//  - Codable (so it can cross phone ↔ watch via WatchConnectivity)
//  - Value-typed (so it can be cached, diffed, and transported cheaply)
//

import Foundation

public enum DeviceControllerKind: String, Codable, Sendable {
  case tv
  case streamer
  case paired
}

/// A stable "whole device" descriptor.
///
/// Identity rules (Joe's spec):
/// - TV alone: tvId
/// - Streamer alone: streamerId
/// - Paired: "tvId:streamerId"
public struct DeviceControllerDescriptor: Codable, Equatable, Sendable, Identifiable {
  public var id: String

  public var kind: DeviceControllerKind

  /// Human-friendly display name for selection UI (e.g. TV name for paired targets).
  public var displayName: String

  /// Optional room/location.
  public var location: String?

  /// Underlying endpoint IDs (Roku serial-number / device-id today).
  public var tvId: String?
  public var streamerId: String?

  /// Endpoint that owns navigation/app/transport/etc commands.
  public var controlEndpointId: String

  /// Endpoint that owns power/volume (if available).
  public var hardwareEndpointId: String?

  public init(
    id: String,
    kind: DeviceControllerKind,
    displayName: String,
    location: String?,
    tvId: String?,
    streamerId: String?,
    controlEndpointId: String,
    hardwareEndpointId: String?
  ) {
    self.id = id
    self.kind = kind
    self.displayName = displayName
    self.location = location
    self.tvId = tvId
    self.streamerId = streamerId
    self.controlEndpointId = controlEndpointId
    self.hardwareEndpointId = hardwareEndpointId
  }

  public static func pairedId(tvId: String, streamerId: String) -> String {
    "\(tvId):\(streamerId)"
  }

  public func containsEndpoint(_ endpointId: String) -> Bool {
    endpointId == tvId || endpointId == streamerId || endpointId == controlEndpointId || endpointId == hardwareEndpointId
  }
}
