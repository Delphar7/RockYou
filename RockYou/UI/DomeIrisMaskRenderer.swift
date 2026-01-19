// DomeIrisMaskRenderer.swift
// RockYou
//
// Rasterizes the 2D iris mask for debug views and texture previews.

import CoreGraphics
import Foundation
import simd

enum DomeIrisMaskRenderer {

  // Debug-only overlays baked into the CPU mask texture.
  static let enableSeams = true
  static let seamsOnClosedOnly = true
  static let seamStrength: Float = 0.25

  static let enableEdgeBand = true
  static let edgeBandInner: Float = 0.02
  static let edgeBandOuter: Float = 0.05
  static let edgeBandStrength: Float = 0.35

  static func makeMaskImage(
    size: Int,
    t: Float,
    bladeCount: Int,
    config: DomeIrisConfig,
    flipY: Bool = true
  ) -> CGImage? {
    let width = max(1, size)
    let height = max(1, size)
    var buffer = [UInt8](repeating: 0, count: width * height)

    let invW = 1 / Float(width)
    let invH = 1 / Float(height)

    for y in 0..<height {
      let v = (Float(y) + 0.5) * invH
      // flipY=true matches the existing dome texture orientation (keep as default).
      // flipY=false is useful for matching the dome's apparent rotation direction in 2D debug.
      let py = (flipY ? (1 - v) : v) * 2 - 1

      for x in 0..<width {
        let u = (Float(x) + 0.5) * invW
        let px = u * 2 - 1

        let p = SIMD2<Float>(px, py)
        let m = DomeIrisAnimation.mask(
          p: p,
          t: t,
          bladeCount: bladeCount,
          config: config
        )

        var value = m

        if enableSeams {
          let theta = atan2(p.y, p.x)
          let r = min(1, simd_length(p))

          let seam = DomeIrisAnimation.seamMask(
            theta: theta,
            r: r,
            u: t,
            bladeCount: bladeCount,
            config: config
          )

          if seamsOnClosedOnly {
            // seams brighten the covered area only (keeps the hole clean/white)
            value = value + (1 - m) * (seamStrength * seam)
          } else {
            value = value + seamStrength * seam
          }
        }

        if enableEdgeBand {
          // Boundary is around m ~= 0.5 because mask is a smoothstep of signed distance.
          let distToEdge = abs(m - 0.5)
          let edgeBand = 1 - DomeIrisAnimation.smoothstep(edgeBandInner, edgeBandOuter, distToEdge)
          value = DomeIrisAnimation.clamp(value - edgeBandStrength * edgeBand)
        }

        buffer[y * width + x] = UInt8(DomeIrisAnimation.clamp(value) * 255)
      }
    }

    let data = Data(buffer)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}
