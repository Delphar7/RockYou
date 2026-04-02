//
//  ConnectionStatusDot.swift
//  RockYou (Shared)
//
//  Shows device connection/power state as a colored dot.
//

import SwiftUI

/// Shows device power/connection state as a colored dot or wifi animation.
/// Green = on, Orange = standby/unknown, Red = off, Wifi animation = (re)connecting.
public struct ConnectionStatusDot: View {
  let deviceId: String?

  public init(deviceId: String?) {
    self.deviceId = deviceId
  }

  public var body: some View {
    if isConnecting {
      Image(systemName: "wifi.circle.fill")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.white)
        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
        .font(.system(size: 12))
    } else {
      Circle()
        .fill(currentPowerMode.statusColor)
        .frame(width: 8, height: 8)
    }
  }

  private var isConnecting: Bool {
    guard let id = deviceId else { return false }
    return DeviceStateManager.shared.connectingDeviceIds.contains(id)
  }

  private var currentPowerMode: PowerMode {
    guard let id = deviceId else { return .unknown }
    return DeviceStateManager.shared.state(for: id).powerMode
  }
}

#Preview {
  HStack(spacing: 20) {
    ConnectionStatusDot(deviceId: nil)
    ConnectionStatusDot(deviceId: "ABC123")
  }
  .padding()
  .background(Color.black)
}
