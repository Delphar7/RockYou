//
//  PlatformImage.swift
//  RockYou (Shared)
//
//  Centralized, cross-platform image loader + cache.
//  - Abstracts NSImage vs UIImage
//  - Centralizes disk-load + decode
//  - Adds in-memory cache to avoid repeated PNG decode during SwiftUI recomputes (e.g. resizing)
//

import Foundation
import SwiftUI
import CoreGraphics
import os.lock

#if canImport(AppKit)
import AppKit
public typealias PlatformNativeImage = NSImage
#else
import UIKit
public typealias PlatformNativeImage = UIImage
#endif

/// Central image loader/cacher for platform-native images.
///
/// Notes:
/// - Keyed by full file path (NSString) to avoid ambiguity.
/// - Intended for small-ish assets we frequently redraw (icons, textures).
public enum PlatformImage {
  private static let cache = NSCache<NSString, PlatformNativeImage>()

  // Debug-only instrumentation for cache hit/miss behavior during resize profiling.
  // Uses async-safe locking to avoid Swift 6 concurrency warnings.
  private struct DebugState {
    var hits: Int = 0
    var misses: Int = 0
    var loads: Int = 0
    var failures: Int = 0
    var purges: Int = 0

    var lastLogUptime: TimeInterval = 0
    var lastLoggedHits: Int = 0
    var lastLoggedMisses: Int = 0
    var lastLoggedLoads: Int = 0
    var lastLoggedFailures: Int = 0
    var lastLoggedPurges: Int = 0

    var lastMissFile: String = ""
  }

  private static let debugStateLock = OSAllocatedUnfairLock(initialState: DebugState())

  private static func debugNote(
    platform: String,
    hit: Bool? = nil,
    loaded: Bool? = nil,
    failure: Bool = false,
    purge: Bool = false,
    path: String
  ) {
    DebugBuild.run {
      let now = ProcessInfo.processInfo.systemUptime
      let file = URL(fileURLWithPath: path).lastPathComponent

      debugStateLock.withLock { state in
        if let hit, hit { state.hits += 1 }
        if let hit, hit == false {
          state.misses += 1
          state.lastMissFile = file
        }
        if let loaded, loaded { state.loads += 1 }
        if failure { state.failures += 1 }
        if purge { state.purges += 1 }

        // Throttle: log at most every ~0.75s and only if something changed.
        let shouldLog = (now - state.lastLogUptime) >= 0.75
        guard shouldLog else { return }

        let dh = state.hits - state.lastLoggedHits
        let dm = state.misses - state.lastLoggedMisses
        let dl = state.loads - state.lastLoggedLoads
        let df = state.failures - state.lastLoggedFailures
        let dp = state.purges - state.lastLoggedPurges

        guard (dh + dm + dl + df + dp) > 0 else { return }

        state.lastLogUptime = now
        state.lastLoggedHits = state.hits
        state.lastLoggedMisses = state.misses
        state.lastLoggedLoads = state.loads
        state.lastLoggedFailures = state.failures
        state.lastLoggedPurges = state.purges

        let missFile = state.lastMissFile.isEmpty ? "-" : state.lastMissFile
        Log.info(
          "ImageCache",
          "\(platform) hits=\(state.hits) misses=\(state.misses) loads=\(state.loads) failures=\(state.failures) purges=\(state.purges) " +
            "Δ[h=\(dh) m=\(dm) l=\(dl) f=\(df) p=\(dp)] lastMiss=\(missFile)"
        )
      }
    }
  }

  // MARK: - Native Image API

  public static func nativeContentsOfFile(_ path: String) -> PlatformNativeImage? {
    PlatformNativeImage(contentsOfFile: path)
  }

  public static func cachedNativeContentsOfFile(_ path: String) -> PlatformNativeImage? {
    let key = path as NSString
    if let cached = cache.object(forKey: key) {
      debugNote(platform: platformLabel, hit: true, path: path)
      return cached
    }
    debugNote(platform: platformLabel, hit: false, path: path)
    guard let image = PlatformNativeImage(contentsOfFile: path) else {
      debugNote(platform: platformLabel, failure: true, path: path)
      return nil
    }
    cache.setObject(image, forKey: key)
    debugNote(platform: platformLabel, loaded: true, path: path)
    return image
  }

  // MARK: - SwiftUI Image Convenience

  public static func contentsOfFile(_ path: String) -> Image? {
    guard let native = nativeContentsOfFile(path) else { return nil }
    return swiftUIImage(from: native)
  }

  public static func cachedContentsOfFile(_ path: String) -> Image? {
    guard let native = cachedNativeContentsOfFile(path) else { return nil }
    return swiftUIImage(from: native)
  }

  public static func purgeCache(for path: String) {
    cache.removeObject(forKey: path as NSString)
    debugNote(platform: platformLabel, purge: true, path: path)
  }

  public static func purgeAllCache() {
    cache.removeAllObjects()
    debugNote(platform: platformLabel, purge: true, path: "<all>")
  }

  // MARK: - Internals

  private static var platformLabel: String {
#if os(macOS)
    return "macOS"
#elseif os(watchOS)
    return "watchOS"
#else
    return "iOS"
#endif
  }

  public static func swiftUIImage(from native: PlatformNativeImage) -> Image {
#if canImport(AppKit)
    return Image(nsImage: native)
#else
    return Image(uiImage: native)
#endif
  }

  /// Best-effort extraction of a `CGImage` from a platform-native image.
  ///
  /// Useful for debug pixel inspection and other cross-platform image analysis.
  public static func cgImage(from native: PlatformNativeImage) -> CGImage? {
#if canImport(AppKit)
    var rect = CGRect(origin: .zero, size: native.size)
    return native.cgImage(forProposedRect: &rect, context: nil, hints: nil)
#else
    return native.cgImage
#endif
  }

  // MARK: - Edge Luminance

  /// Compute weighted average luminance along all four edges of the image.
  ///
  /// Algorithm: start `inset` pixels inward (to skip borders/transparency), then
  /// sample `depth` rows/columns further inward with diminishing weight.
  /// Returns 0 (black) … 1 (white), or `nil` if the image is too small or unreadable.
  public static func edgeLuminance(of native: PlatformNativeImage) -> CGFloat? {
    guard let cg = cgImage(from: native) else { return nil }
    let w = cg.width
    let h = cg.height

    // Need enough room for inset + sample depth on each side.
    guard w >= 18, h >= 18 else { return nil }

    // Render into a known RGBA8 layout so pixel math is predictable.
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let rowBytes = w * 4
    guard let ctx = CGContext(
      data: nil, width: w, height: h,
      bitsPerComponent: 8, bytesPerRow: rowBytes,
      space: colorSpace, bitmapInfo: bitmapInfo
    ) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

    // Anchor row/col is `inset` pixels from the edge (weight 1.0).
    // Sample 4 pixels shallower (toward edge) and 4 deeper (toward center)
    // with diminishing weight by distance from the anchor.
    let inset = 5
    let spread = 4
    // offsets: -4, -3, -2, -1, 0, +1, +2, +3, +4  (0 = anchor at `inset`)
    // weights:  0.25, 0.5, 0.75, 1.0, 1.0, 1.0, 0.75, 0.5, 0.25
    let offsets: [Int]     = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
    let weights: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.0, 1.0, 0.75, 0.5, 0.25]

    var totalLuminance: CGFloat = 0
    var totalWeight: CGFloat = 0

    func sample(x: Int, y: Int, weight: CGFloat) {
      guard x >= 0, x < w, y >= 0, y < h else { return }
      let off = y * rowBytes + x * 4
      let a = CGFloat(pixels[off + 3]) / 255.0
      guard a > 0.1 else { return }  // skip transparent pixels
      // Un-premultiply
      let r = CGFloat(pixels[off]) / (255.0 * a)
      let g = CGFloat(pixels[off + 1]) / (255.0 * a)
      let b = CGFloat(pixels[off + 2]) / (255.0 * a)
      let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b  // BT.709
      totalLuminance += lum * weight
      totalWeight += weight
    }

    // Top edge: sample rows around y=inset, sweep columns from inset to w-inset
    for (i, d) in offsets.enumerated() {
      let y = inset + d
      for x in (inset - spread)..<(w - inset + spread) {
        sample(x: x, y: y, weight: weights[i])
      }
    }
    // Bottom edge
    for (i, d) in offsets.enumerated() {
      let y = h - 1 - inset - d
      for x in (inset - spread)..<(w - inset + spread) {
        sample(x: x, y: y, weight: weights[i])
      }
    }
    // Left edge
    for (i, d) in offsets.enumerated() {
      let x = inset + d
      for y in (inset - spread)..<(h - inset + spread) {
        sample(x: x, y: y, weight: weights[i])
      }
    }
    // Right edge
    for (i, d) in offsets.enumerated() {
      let x = w - 1 - inset - d
      for y in (inset - spread)..<(h - inset + spread) {
        sample(x: x, y: y, weight: weights[i])
      }
    }

    guard totalWeight > 0 else { return nil }
    return totalLuminance / totalWeight
  }
}

/// Backwards compatibility: keep existing call sites working (`PlatformSwiftUIImage.cachedContentsOfFile`).
public typealias PlatformSwiftUIImage = PlatformImage
