import Foundation
import CoreGraphics
import UIKit

enum PlatformDevice {
  static var isPad: Bool {
    UIDevice.current.userInterfaceIdiom == .pad
  }
}

enum PlatformScreen {
  static var mainBounds: CGRect {
    UIScreen.main.bounds
  }
}

enum PlatformURLHandler {
  static func canOpen(_ url: URL) -> Bool {
    UIApplication.shared.canOpenURL(url)
  }

  static func open(_ url: URL) {
    UIApplication.shared.open(url)
  }

  static func openAppSettingsFallback() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }
}
