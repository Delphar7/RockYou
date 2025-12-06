import SwiftUI

/// Shared accessor for the platform-specific device state provider (iOS/macOS).
@MainActor
enum DeviceSelectionProvider {
  static var selectedDeviceId: String? {
    iOSDeviceStateProvider.shared.selectedDeviceId
  }

  static var provider: DeviceStateProviding {
    iOSDeviceStateProvider.shared
  }
}
