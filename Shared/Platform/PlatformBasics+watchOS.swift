import CoreGraphics
import Foundation
import UIKit
import WatchKit

enum PlatformDevice {
  static var isPad: Bool { false }
}

enum PlatformScreen {
  static var mainBounds: CGRect {
    WKInterfaceDevice.current().screenBounds
  }
}

enum PlatformURLHandler {
  static func canOpen(_ url: URL) -> Bool {
    _ = url
    // watchOS doesn't expose a preflight "canOpen" API; allow caller to attempt.
    return true
  }

  static func open(_ url: URL) {
    WKApplication.shared().openSystemURL(url)
  }

  static func openAppSettingsFallback() {
    // no-op
  }
}
