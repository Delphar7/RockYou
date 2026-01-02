//
//  DeviceControllerBuilder.swift
//  RockYou (iOS/macOS)
//
//  Builds "whole device" controller descriptors from:
//  - discovered endpoints (RokuDiscoveryService)
//  - configured pairings (PairingStore)
//

import Foundation

@MainActor
enum DeviceControllerBuilder {
  static func buildControllers(
    discovered: [DeviceInfo],
    pairings: [TVPairing]
  ) -> [DeviceControllerDescriptor] {
    let byId: [String: DeviceInfo] = Dictionary(uniqueKeysWithValues: discovered.map { ($0.id, $0) })

    var controllers: [DeviceControllerDescriptor] = []
    controllers.reserveCapacity(discovered.count)

    // Pair controllers first.
    for pairing in pairings {
      let tv = byId[pairing.tvId]
      let streamer = byId[pairing.streamerId]

      // If neither endpoint is currently known, skip.
      if tv == nil, streamer == nil { continue }

      if let tv, let streamer {
        controllers.append(
          DeviceControllerDescriptor(
            id: DeviceControllerDescriptor.pairedId(tvId: tv.id, streamerId: streamer.id),
            kind: .paired,
            displayName: tv.name,
            location: tv.location ?? streamer.location,
            tvId: tv.id,
            streamerId: streamer.id,
            controlEndpointId: streamer.id,
            hardwareEndpointId: tv.id
          )
        )
      } else if let tv {
        controllers.append(
          DeviceControllerDescriptor(
            id: tv.id,
            kind: .tv,
            displayName: tv.name,
            location: tv.location,
            tvId: tv.id,
            streamerId: nil,
            controlEndpointId: tv.id,
            hardwareEndpointId: tv.id
          )
        )
      } else if let streamer {
        controllers.append(
          DeviceControllerDescriptor(
            id: streamer.id,
            kind: .streamer,
            displayName: streamer.name,
            location: streamer.location,
            tvId: nil,
            streamerId: streamer.id,
            controlEndpointId: streamer.id,
            hardwareEndpointId: nil
          )
        )
      }
    }

    // Add unpaired endpoints as single controllers.
    let pairedEndpointIds = Set(pairings.flatMap { [$0.tvId, $0.streamerId] })
    for device in discovered where !pairedEndpointIds.contains(device.id) {
      controllers.append(
        DeviceControllerDescriptor(
          id: device.id,
          kind: device.isTV ? .tv : .streamer,
          displayName: device.name,
          location: device.location,
          tvId: device.isTV ? device.id : nil,
          streamerId: device.isTV ? nil : device.id,
          controlEndpointId: device.id,
          hardwareEndpointId: device.isTV ? device.id : nil
        )
      )
    }

    // De-dupe by id (paranoia).
    var seen = Set<String>()
    controllers.removeAll { !seen.insert($0.id).inserted }

    // Stable-ish ordering: location, then name, then id.
    controllers.sort {
      let lhsLoc = ($0.location ?? "").localizedCaseInsensitiveCompare($1.location ?? "")
      if lhsLoc != .orderedSame { return lhsLoc == .orderedAscending }
      let lhsName = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
      if lhsName != .orderedSame { return lhsName == .orderedAscending }
      return $0.id < $1.id
    }

    return controllers
  }
}
