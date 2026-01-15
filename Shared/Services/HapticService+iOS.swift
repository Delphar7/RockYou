import SwiftUI

import UIKit

extension HapticType {
  fileprivate var iOSImpactStyle: UIImpactFeedbackGenerator.FeedbackStyle {
    switch self {
    case .click: return .light
    case .success: return .medium
    case .warning: return .heavy
    case .start: return .soft
    case .rigid: return .rigid
    }
  }
}

extension HapticService {
  fileprivate static func platformPlay(_ type: HapticType) {
    let generator = UIImpactFeedbackGenerator(style: type.iOSImpactStyle)
    generator.impactOccurred()
  }

  fileprivate static func platformNotifySuccess() {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
  }

  fileprivate static func platformNotifyWarning() {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.warning)
  }
}
