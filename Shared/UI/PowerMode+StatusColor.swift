import SwiftUI

public extension PowerMode {
  /// Status dot color for UI.
  var statusColor: Color {
    switch self {
    case .on:
      return powerButtonDarkGreen
    case .ready:
      return .orange
    case .off, .displayOff:
      return .red
    case .unknown:
      return .orange
    }
  }
}
