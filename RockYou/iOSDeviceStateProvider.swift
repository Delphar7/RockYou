//
//  iOSDeviceStateProvider.swift
//  RockYou
//
//  iOS implementation of DeviceStateProviding.
//  Now simply delegates to shared DeviceStateManager.
//

import SwiftUI

/// iOS/macOS device state provider - delegates to DeviceStateManager
/// Note: Not ObservableObject since state is @Observable via DeviceStateManager
@MainActor
final class iOSDeviceStateProvider: DeviceStateProviding {
  static let shared = iOSDeviceStateProvider()

  private let pairingStore = PairingStore.shared

  private init() {}

  // MARK: - DeviceStateProviding

  /// Selected device is derived from pairing store
  var selectedDeviceId: String? {
    if let selection = pairingStore.currentSelection {
      switch selection {
      case .tv(let id):
        // If there's a paired streamer, use that.
        if let streamerId = pairingStore.streamerIdForTV(id) {
          return streamerId
        }
        return id
      case .streamer(let id):
        return id
      }
    }

    guard let tvId = pairingStore.currentTVId else { return nil }
    // If there's a paired streamer, use that
    if let streamerId = pairingStore.streamerIdForTV(tvId) {
      return streamerId
    }
    return tvId
  }

  func powerMode(for deviceId: String) -> PowerMode {
    DeviceStateManager.shared.state(for: deviceId).powerMode
  }

  func deviceState(for deviceId: String) -> DeviceState {
    DeviceStateManager.shared.state(for: deviceId)
  }
}
