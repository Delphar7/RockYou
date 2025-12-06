import CoreGraphics
import SwiftUI
import UIKit

typealias OSColor = UIColor

extension Color {
  func rgbaComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
    let c = OSColor(self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (r, g, b, a)
  }

  var rgbaComponentsOrZero: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    rgbaComponents() ?? (0, 0, 0, 0)
  }
}
