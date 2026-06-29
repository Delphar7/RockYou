//
//  BreakerSwitchSnapshotManager.swift
//  RockYou
//
//  Renders BreakerSwitchView to a static platform-native image for idle display.
//  Uses ARView.snapshot() which works with Metal-backed content.
//

import Combine
import CoreGraphics
import RealityKit
import SwiftUI

@MainActor
final class BreakerSwitchSnapshotManager: ObservableObject {
  static let shared = BreakerSwitchSnapshotManager()

  @Published private(set) var snapshot: PlatformNativeImage? {
    didSet {
      DebugBuild.run {
        if snapshot == nil, oldValue != nil {
          Log.warn("BreakerSwitch", "📸 Snapshot cleared (was non-nil)")
        } else if snapshot != nil, oldValue == nil {
          Log.debug("BreakerSwitch", "📸 Snapshot set (was nil)")
        }
      }
    }
  }
  private var renderTimer: Timer?
  private var currentSize: CGSize = .zero

  /// Single-flight guard: only one offscreen `ARView` may render at a time. Two concurrent
  /// offscreen renderers would race on the shared breaker GPU resources. A request that
  /// arrives mid-render is coalesced and run once the in-flight render finishes.
  private var isRendering = false
  private var pendingRender: (size: CGSize, reason: String)?

  // Snapshot configuration
  private let snapshotInitialDelaySeconds: TimeInterval = 2.0
  /// Prefer waiting for actual frame/update ticks over blind sleeps, but keep a small fallback.
  private let snapshotWarmupFallbackDelay: Duration = .milliseconds(100)
  private let snapshotWarmupFramesToWait: Int = 4
  private let snapshotWarmupMaxAttempts: Int = 3

  private init() {}

  /// Call when the display size changes. Schedules a deferred render.
  ///
  /// If no snapshot exists yet, we render immediately (to avoid the first-lock case where
  /// a debounced timer hasn't fired yet).
  func requestSnapshot(size: CGSize) {
    // Offscreen `ARView` snapshotting asserts in MPS (VideoLightSpillGenerator warm-up) on the
    // simulator's software-Metal stack under the Xcode 27 / SDK 26 beta. The live `RealityView`
    // path is unaffected, so the static-snapshot optimization is disabled on the simulator.
    #if !targetEnvironment(simulator)
    guard size.width > 0, size.height > 0 else { return }
    guard size != currentSize || snapshot == nil else { return }
    currentSize = size

    // Delay first snapshot to avoid capturing an under-lit first frame
    if snapshot == nil {
      renderTimer?.invalidate()
      let delay = snapshotInitialDelaySeconds
      if delay <= 0 {
        Task { @MainActor in
          await self.renderSnapshot(size: size, reason: "initial")
        }
      } else {
        renderTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) {
          [weak self] _ in
          Task { @MainActor in
            await self?.renderSnapshot(size: size, reason: "initial-delayed")
          }
        }
      }
      return
    }

    // Debounce: wait for size to settle (e.g., during iPad window resize)
    renderTimer?.invalidate()
    let delay: TimeInterval = DebugBuild.isEnabled ? 1.0 : 2.0
    renderTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      Task { @MainActor in
        await self?.renderSnapshot(size: size, reason: "debounced")
      }
    }
    #endif
  }

  /// Forces a snapshot render immediately (no debounce). Intended for the lock overlay path.
  func forceSnapshot(size: CGSize, reason: String) {
    // Disabled on the simulator — see `requestSnapshot` (ARView/MPS warm-up assert under the beta).
    #if !targetEnvironment(simulator)
    guard size.width > 0, size.height > 0 else { return }
    currentSize = size
    renderTimer?.invalidate()
    renderTimer = nil
    Task { @MainActor in
      await self.renderSnapshot(size: size, reason: reason)
    }
    #endif
  }

  private func renderSnapshot(size: CGSize, reason: String) async {
    // NOTE: On the simulator this is never reached — `requestSnapshot`/`forceSnapshot` (the only
    // callers) short-circuit before scheduling, because the offscreen `ARView` asserts in MPS
    // (VideoLightSpillGenerator warm-up) on the beta simulator's software-Metal stack.

    // Single-flight: never run two offscreen ARViews at once. Coalesce to the latest request.
    guard !isRendering else {
      pendingRender = (size, reason)
      DebugBuild.run {
        Log.debug("BreakerSwitch", "📸 Snapshot render coalesced (busy) reason=\(reason)")
      }
      return
    }
    isRendering = true
    defer {
      isRendering = false
      if let next = pendingRender {
        pendingRender = nil
        Task { @MainActor in await self.renderSnapshot(size: next.size, reason: next.reason) }
      }
    }

    // Release-safe breadcrumb: the offscreen RealityKit render is the first GPU work at launch.
    Log.info("BreakerSwitch", "Offscreen snapshot render begin reason=\(reason)")

    DebugBuild.run {
      Log.debug(
        "BreakerSwitch",
        "📸 Snapshot render start reason=\(reason) size=\(Int(size.width))x\(Int(size.height)) hasPrev=\(snapshot != nil ? "true" : "false")"
      )
    }

    // Create a temporary ARView sized to match
    let view = ARView(frame: CGRect(origin: .zero, size: size))
    // Use transparent background so snapshot composites cleanly over the ellipse
    view.environment.background = .color(.clear)
    prepareARViewForSnapshot(view)

    _ = attachOffscreenARViewToWindow(view, size: size)

    // Add camera + lighting (shared rig)
    view.scene.addAnchor(makeBreakerCameraAnchor())
    view.scene.addAnchor(makeBreakerLightAnchor())

    // Debug: Add XYZ axes at origin (where model is)
    if let axes = makeDebugAxes() {
      let axesAnchor = AnchorEntity(world: .zero)
      axesAnchor.addChild(axes)
      view.scene.addAnchor(axesAnchor)
    }

    // Load model — `makeInstance()` returns our own clone, so the live view can't
    // steal or mutate our entity mid-snapshot.
    do {
      let entity = try await BreakerModelCache.shared.makeInstance()
      _ = prepareBreakerEntityForDisplay(entity)

      // Validation gate: don't render a malformed model (non-geometry entities, or
      // non-finite/inverted mesh bounds). Handing that to the renderer risks a crash
      // deep in CoreRE with no app frames on the stack.
      if let reason = validateBreakerModelIsClean(entity)
        ?? RenderResourceValidation.validate(entity: entity, label: "breaker-snapshot")
      {
        Log.error("BreakerSwitch", "📸 Snapshot skipped — invalid model: \(reason)")
        view.removeFromSuperview()
        return
      }

      let anchor = AnchorEntity(world: .zero)
      anchor.addChild(entity)
      view.scene.addAnchor(anchor)

      var finalImage: PlatformNativeImage? = nil
      for attempt in 1...snapshotWarmupMaxAttempts {
        let framesWaited = await waitForSceneUpdates(
          view: view,
          frames: snapshotWarmupFramesToWait,
          timeout: .seconds(2)
        )
        DebugBuild.run {
          Log.debug(
            "BreakerSwitch",
            "📸 Snapshot warmup attempt=\(attempt) waitedFrames=\(framesWaited)/\(snapshotWarmupFramesToWait) reason=\(reason)"
          )
        }

        // If updates aren't ticking for some reason, still try a tiny delay before snapshot.
        if framesWaited == 0 {
          try? await Task.sleep(for: snapshotWarmupFallbackDelay)
        }

        let image = await takeSnapshot(view)
        if let image {
          DebugBuild.run {
            let stats = debugImageStats(image)
            Log.debug(
              "BreakerSwitch",
              "📸 Snapshot render gotImage attempt=\(attempt) reason=\(reason) size=\(Int(size.width))x\(Int(size.height)) image=\(Int(image.size.width))x\(Int(image.size.height)) stats=\(stats)"
            )
          }

          // If the image is plausibly blank, retry a couple times.
          if DebugBuild.isEnabled, debugIsProbablyBlank(image) {
            DebugBuild.run {
              Log.warn(
                "BreakerSwitch",
                "📸 Snapshot looks blank attempt=\(attempt) reason=\(reason) (retrying)"
              )
            }
          } else {
            finalImage = image
            break
          }
        } else {
          DebugBuild.run {
            Log.warn(
              "BreakerSwitch",
              "📸 Snapshot render returned nil attempt=\(attempt) reason=\(reason) size=\(Int(size.width))x\(Int(size.height))"
            )
          }
        }
      }

      if let finalImage {
        self.snapshot = finalImage
      }

      // Tear down only after the render thread has settled. The snapshot callback fires
      // post-frame, but detaching the ARView (and releasing its scene/resources)
      // synchronously can still race an in-flight frame on RealityKit's render thread.
      // Wait one more bounded update tick before detaching.
      _ = await waitForSceneUpdates(view: view, frames: 1, timeout: .seconds(1))
      view.removeFromSuperview()
      Log.info(
        "BreakerSwitch",
        "Offscreen snapshot render done reason=\(reason) gotImage=\(finalImage != nil)")
    } catch {
      Log.error("BreakerSwitch", "Snapshot render failed: \(error)")
      view.removeFromSuperview()
    }
  }
}

// MARK: - Debug pixel sampling

// NOTE:
// This sampling code is intentionally simple and DEBUG-only. If we ever want richer/faster
// surface stats (mean alpha/luminance, “has color but all alpha”, “not purple”, etc.),
// consider swapping this implementation to a Core Image reduction pass (e.g. `CIAreaAverage`)
// rendered to a 1×1 pixel buffer. That would leverage the GPU and gives a clean “summary”
// signal without scanning the whole image on CPU.  Given this is ignoring stride, line end
// alignment padding, and color bit depth, ordering, or compression... it's worth updating if
// it ever is doing more than 'is it blank/black?'

@MainActor
private func takeSnapshot(_ view: ARView) async -> PlatformNativeImage? {
  await withCheckedContinuation { cont in
    view.snapshot(saveToHDR: false) { image in
      cont.resume(returning: image)
    }
  }
}

@MainActor
private func waitForSceneUpdates(view: ARView, frames: Int, timeout: Duration) async -> Int {
  guard frames > 0 else { return 0 }
  let stream = AsyncStream<Void> { continuation in
    let sub = view.scene.subscribe(to: SceneEvents.Update.self) { _ in
      continuation.yield(())
    }
    continuation.onTermination = { _ in
      sub.cancel()
    }
  }

  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)

  var waited = 0
  var it = stream.makeAsyncIterator()
  while waited < frames {
    // Timeout check
    if clock.now >= deadline { break }
    guard let _ = await it.next() else { break }
    waited += 1
  }
  return waited
}

private func debugImageStats(_ image: PlatformNativeImage) -> String {
  guard let cgImage = PlatformImage.cgImage(from: image) else { return "cgImage=nil" }
  guard let data = cgImage.dataProvider?.data as Data? else { return "data=nil" }
  let w = cgImage.width
  let h = cgImage.height
  let bpp = cgImage.bitsPerPixel
  let bpc = cgImage.bitsPerComponent
  let bpr = cgImage.bytesPerRow

  // Very rough heuristic: sample a 4x4 grid of pixels, count transparent & near-black.
  func sample(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    guard x >= 0, x < w, y >= 0, y < h else { return nil }
    // Assume common 32-bit RGBA/BGRA formats from UIKit/AppKit snapshots.
    // We don't try to perfectly decode all pixel formats; this is debug-only.
    let offset = y * bpr + x * (bpp / 8)
    guard offset + 3 < data.count else { return nil }
    let p0 = data[offset + 0]
    let p1 = data[offset + 1]
    let p2 = data[offset + 2]
    let p3 = data[offset + 3]

    // Heuristic: treat as RGBA (good enough for debug detection of "all transparent/black").
    return (r: p0, g: p1, b: p2, a: p3)
  }

  var total = 0
  var transparent = 0
  var nearBlack = 0
  for gy in 0..<4 {
    for gx in 0..<4 {
      let x = (w - 1) * gx / 3
      let y = (h - 1) * gy / 3
      guard let px = sample(x: x, y: y) else { continue }
      total += 1
      if px.a <= 8 { transparent += 1 }
      if px.r <= 8 && px.g <= 8 && px.b <= 8 { nearBlack += 1 }
    }
  }
  return
    "w=\(w) h=\(h) bpc=\(bpc) bpp=\(bpp) samples=\(total) transparent=\(transparent) nearBlack=\(nearBlack)"
}

private func debugIsProbablyBlank(_ image: PlatformNativeImage) -> Bool {
  guard let cgImage = PlatformImage.cgImage(from: image) else { return true }
  guard let data = cgImage.dataProvider?.data as Data? else { return true }
  let w = cgImage.width
  let h = cgImage.height
  let bpp = cgImage.bitsPerPixel
  let bpr = cgImage.bytesPerRow
  guard bpp >= 32 else { return false }

  func sample(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    let offset = y * bpr + x * (bpp / 8)
    guard offset + 3 < data.count else { return nil }
    return (r: data[offset + 0], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
  }

  var total = 0
  var transparent = 0
  var nearBlack = 0
  for gy in 0..<4 {
    for gx in 0..<4 {
      let x = (w - 1) * gx / 3
      let y = (h - 1) * gy / 3
      guard let px = sample(x: x, y: y) else { continue }
      total += 1
      if px.a <= 8 { transparent += 1 }
      if px.r <= 8 && px.g <= 8 && px.b <= 8 { nearBlack += 1 }
    }
  }

  // If virtually all sampled pixels are transparent or near-black, call it blank.
  let threshold = max(1, total - 1)
  return transparent >= threshold || nearBlack >= threshold
}
