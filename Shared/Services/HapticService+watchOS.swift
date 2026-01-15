import SwiftUI

import WatchKit

extension HapticType {
  fileprivate var watchOSType: WKHapticType {
    switch self {
    case .click: return .click
    case .success: return .success
    case .warning: return .notification
    case .start: return .start
    case .rigid: return .directionUp  // Strong haptic for heavy impact
    }
  }
}

extension HapticService {
  fileprivate static func platformPlay(_ type: HapticType) {
    WKInterfaceDevice.current().play(type.watchOSType)
  }

  fileprivate static func platformNotifySuccess() {
    WKInterfaceDevice.current().play(.success)
  }

  fileprivate static func platformNotifyWarning() {
    WKInterfaceDevice.current().play(.notification)
  }
}
