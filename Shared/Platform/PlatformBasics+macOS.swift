import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum PlatformDevice {
  static var isPad: Bool { false }
}

enum PlatformScreen {
  static var mainBounds: CGRect {
    NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
  }
}

enum PlatformURLHandler {
  static func canOpen(_ url: URL) -> Bool {
    NSWorkspace.shared.urlForApplication(toOpen: url) != nil
  }

  static func open(_ url: URL) {
    _ = NSWorkspace.shared.open(url)
  }

  static func openAppSettingsFallback() {
    // no-op
  }
}

enum PlatformSwiftUIImage {
  static func contentsOfFile(_ path: String) -> Image? {
    guard let nsImage = NSImage(contentsOfFile: path) else { return nil }
    return Image(nsImage: nsImage)
  }
}
