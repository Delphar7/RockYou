import Foundation

@MainActor
struct RemoteControlSelection {
  let pairingStore: PairingStore
  let discovery: RokuDiscoveryService

  var hardwareControlsAvailable: Bool {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv: return true
      case .streamer: return false
      }
    }
    return pairingStore.currentTVId != nil
  }

  var selectedTVName: String? {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let tvId):
        if let pairing = pairingStore.pairingForTV(tvId) {
          return pairing.tvName
        }
        return discovery.tvs.first { $0.id == tvId }?.name
      case .streamer:
        return nil
      }
    }

    guard let tvId = pairingStore.currentTVId else { return nil }
    if let pairing = pairingStore.currentPairing {
      return pairing.tvName
    }
    return discovery.tvs.first { $0.id == tvId }?.name
  }

  var selectedStreamerName: String? {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv:
        break
      case .streamer(let id):
        return discovery.streamingDevices.first { $0.id == id }?.name
      }
    }

    guard
      let tvId = pairingStore.currentTVId,
      let streamerId = pairingStore.streamerIdForTV(tvId)
    else { return nil }

    if let pairing = pairingStore.currentPairing {
      return pairing.streamerName
    }
    return discovery.streamingDevices.first { $0.id == streamerId }?.name
  }

  var selectedDeviceId: String? {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let tvId):
        if let streamerId = pairingStore.streamerIdForTV(tvId) {
          return streamerId
        }
        return tvId
      case .streamer(let id):
        return id
      }
    }

    guard let tvId = pairingStore.currentTVId else { return nil }
    if let streamerId = pairingStore.streamerIdForTV(tvId) {
      return streamerId
    }
    return tvId
  }

  var selectedDevice: DeviceInfo? {
    guard let deviceId = selectedDeviceId else { return nil }
    return discovery.discoveredDevices.first { $0.id == deviceId }
  }

  var selectedDeviceIP: String? {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let tvId):
        if
          let streamerId = pairingStore.streamerIdForTV(tvId),
          let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId })
        {
          return streamer.ipAddress
        }
        return discovery.tvs.first { $0.id == tvId }?.ipAddress
      case .streamer(let id):
        return discovery.streamingDevices.first { $0.id == id }?.ipAddress
      }
    }

    guard let tvId = pairingStore.currentTVId else { return nil }

    if
      let streamerId = pairingStore.streamerIdForTV(tvId),
      let streamer = discovery.streamingDevices.first(where: { $0.id == streamerId })
    {
      return streamer.ipAddress
    }

    return discovery.tvs.first { $0.id == tvId }?.ipAddress
  }
}
