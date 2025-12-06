import SwiftUI

enum PlatformSafetyDelayLayout {
  static func rowSpacing(hasWatch: Bool) -> CGFloat {
    hasWatch ? 0 : 10
  }

  static var headerYOffset: CGFloat { 10 }

  static var pickerHeight: CGFloat { 75 }
}
