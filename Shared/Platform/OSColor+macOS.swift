import AppKit
import CoreGraphics
import SwiftUI

typealias OSColor = NSColor

extension Color {
  func rgbaComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
    let c = OSColor(self)
    guard let rgb = c.usingColorSpace(.deviceRGB) else { return nil }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
  }

  var rgbaComponentsOrZero: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    rgbaComponents() ?? (0, 0, 0, 0)
  }
}
