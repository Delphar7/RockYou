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
}

/// Backwards compatibility: keep existing call sites working (`PlatformSwiftUIImage.cachedContentsOfFile`).
public typealias PlatformSwiftUIImage = PlatformImage
