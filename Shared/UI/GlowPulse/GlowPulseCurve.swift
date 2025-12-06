import Foundation

enum GlowPulseCurve {
  /// Cosine ease 0→1 with zero slope at endpoints.
  @inline(__always)
  static func ease01(_ x: Double) -> Double {
    0.5 - 0.5 * cos(Double.pi * max(0.0, min(1.0, x)))
  }

  /// Baseline → brighter → off → baseline, parameterized by \(u \in [0,1]\).
  static func opacity(u: Double, baseline base: Double) -> Double {
    let u = max(0.0, min(1.0, u))
    let third = 1.0 / 3.0

    if u < third {
      // baseline → 1
      let s = ease01(u / third)
      return base + ((1.0 - base) * s)
    } else if u < (2.0 * third) {
      // 1 → 0
      let s = ease01((u - third) / third)
      return 1.0 + ((0.0 - 1.0) * s)
    } else {
      // 0 → baseline
      let s = ease01((u - (2.0 * third)) / third)
      return 0.0 + ((base - 0.0) * s)
    }
  }
}
