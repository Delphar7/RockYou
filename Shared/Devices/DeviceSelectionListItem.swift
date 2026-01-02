//
//  DeviceSelectionListItem.swift
//  RockYou (Shared)
//
//  A small, UI-ready “row model” derived from a DeviceControllerDescriptor + endpoint DeviceInfo.
//  Intended to keep list semantics consistent across iOS/macOS/watchOS even when the visual layout differs.
//

import Foundation

public struct DeviceSelectionListItem: Identifiable, Equatable, Sendable {
  public struct Capsule: Equatable, Sendable {
    public var endpointId: String
    public var deviceType: RokuDeviceType
    public var name: String

    public init(endpointId: String, deviceType: RokuDeviceType, name: String) {
      self.endpointId = endpointId
      self.deviceType = deviceType
      self.name = name
    }
  }

  /// Left-side “primary” endpoint id used for icon + power state lookups.
  public var id: String

  /// What gets persisted/selected by the caller.
  public var selectionId: String

  public var deviceType: RokuDeviceType
  public var primaryName: String
  public var secondaryName: String?

  /// Optional right-side capsule (paired device summary).
  public var capsule: Capsule?

  public init(
    id: String,
    selectionId: String,
    deviceType: RokuDeviceType,
    primaryName: String,
    secondaryName: String?,
    capsule: Capsule?
  ) {
    self.id = id
    self.selectionId = selectionId
    self.deviceType = deviceType
    self.primaryName = primaryName
    self.secondaryName = secondaryName
    self.capsule = capsule
  }
}

public enum DeviceSelectionListItemBuilder {
  public enum SelectionIdPolicy: Sendable {
    /// Use `controller.id` (watch-friendly).
    case controllerId
    /// For paired controllers, select by tvId (keeps PairingStore selection semantics); else use controller.id.
    case tvIdForPairedElseControllerId
  }

  /// Global presentation policy (per Joe): paired controllers render with TV primary + streamer capsule.
  public static func build(
    controller: DeviceControllerDescriptor,
    devicesById: [String: DeviceInfo],
    selectionIdPolicy: SelectionIdPolicy
  ) -> DeviceSelectionListItem {
    let tv = controller.tvId.flatMap { devicesById[$0] }
    let streamer = controller.streamerId.flatMap { devicesById[$0] }

    let selectionId: String = {
      switch selectionIdPolicy {
      case .controllerId:
        return controller.id
      case .tvIdForPairedElseControllerId:
        if controller.kind == .paired, let tvId = controller.tvId { return tvId }
        return controller.id
      }
    }()

    switch controller.kind {
    case .tv:
      let id = controller.tvId ?? controller.controlEndpointId
      let name = tv?.name ?? controller.displayName
      let location = tv?.location ?? controller.location
      let secondary = location.map { "\($0) • TV" } ?? "TV"
      return DeviceSelectionListItem(
        id: id,
        selectionId: selectionId,
        deviceType: .tv,
        primaryName: name,
        secondaryName: secondary,
        capsule: nil
      )

    case .streamer:
      let id = controller.streamerId ?? controller.controlEndpointId
      let name = streamer?.name ?? controller.displayName
      let location = streamer?.location ?? controller.location
      let secondary = location.map { "\($0) • Streamer" } ?? "Streamer"
      return DeviceSelectionListItem(
        id: id,
        selectionId: selectionId,
        deviceType: .streamingDevice,
        primaryName: name,
        secondaryName: secondary,
        capsule: nil
      )

    case .paired:
      // TV primary, streamer in capsule.
      let tvId = controller.tvId ?? controller.controlEndpointId
      let tvName = tv?.name ?? controller.displayName
      let tvLocation = tv?.location ?? controller.location

      let capsule: DeviceSelectionListItem.Capsule? = {
        guard let streamerId = controller.streamerId else { return nil }
        let name = streamer?.name ?? "Streamer"
        return .init(endpointId: streamerId, deviceType: .streamingDevice, name: name)
      }()

      return DeviceSelectionListItem(
        id: tvId,
        selectionId: selectionId,
        deviceType: .tv,
        primaryName: tvName,
        secondaryName: tvLocation,
        capsule: capsule
      )
    }
  }
}
