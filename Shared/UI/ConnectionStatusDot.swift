//
//  ConnectionStatusDot.swift
//  RockYou (Shared)
//
//  Shows device connection/power state as a colored dot.
//

import SwiftUI

/// Shows device power state as a colored dot
/// Green = on, Orange = standby/unknown, Red = off
public struct ConnectionStatusDot: View {
  let deviceId: String?

  public init(deviceId: String?) {
    self.deviceId = deviceId
  }

  public var body: some View {
    Circle()
      .fill(currentPowerMode.statusColor)
      .frame(width: 8, height: 8)
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
