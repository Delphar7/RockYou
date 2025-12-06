import CoreGraphics
import Foundation
import SwiftUI
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
    WKExtension.shared().openSystemURL(url)
  }

  static func openAppSettingsFallback() {
    // no-op
  }
}

enum PlatformSwiftUIImage {
  static func contentsOfFile(_ path: String) -> Image? {
    guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
    return Image(uiImage: uiImage)
  }
}
