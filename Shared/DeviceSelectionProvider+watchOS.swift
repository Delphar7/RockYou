import SwiftUI

/// Shared accessor for the platform-specific device state provider (watchOS).
@MainActor
enum DeviceSelectionProvider {
  static var selectedDeviceId: String? {
    ConnectivityManager.shared.selectedDeviceId
  }

  static var provider: DeviceStateProviding {
    ConnectivityManager.shared
  }
}
