import SwiftUI

enum PlatformSafetyDelayLayout {
  static func rowSpacing(hasWatch: Bool) -> CGFloat {
    _ = hasWatch
    return 6
  }

  static var headerYOffset: CGFloat { 0 }

  static var pickerHeight: CGFloat { 28 }
}
