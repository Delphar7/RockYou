//
//  BreakerSwitchView.swift
//  RockYou
//
//  3D breaker switch for dpad unlock mechanism.
//  Uses RealityView (iOS 18+ / macOS 15+) for cross-platform 3D rendering.
//

import Combine
import RealityKit
import SwiftUI

// MARK: - Constants

private let breakerSwitchScale: Float = 1.0
private let breakerSwitchPosition: SIMD3<Float> = [-0.03, 0, -1.5]
private let breakerSwitchFOV: Float = 80  // Degrees - wider = more edge headroom for handle swing

// MARK: - Idle Snapshot (iOS + macOS)

/// Renders BreakerSwitchView to a static platform-native image for idle display.
/// Uses `ARView.snapshot()` which works with Metal-backed content.
@MainActor
final class BreakerSwitchSnapshotManager: ObservableObject {
  static let shared = BreakerSwitchSnapshotManager()

  @Published private(set) var snapshot: PlatformNativeImage?
  private var renderTimer: Timer?
  private var currentSize: CGSize = .zero

  private init() {}

  /// Call when the display size changes. Schedules a deferred render.
  ///
  /// If no snapshot exists yet, we render immediately (to avoid the first-lock case where
  /// a debounced timer hasn't fired yet).
  func requestSnapshot(size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    guard size != currentSize || snapshot == nil else { return }
    currentSize = size

    // First snapshot should happen ASAP so the lock overlay can use it immediately.
    if snapshot == nil {
      Task { @MainActor in
        await self.renderSnapshot(size: size, reason: "initial")
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
  }

  /// Forces a snapshot render immediately (no debounce). Intended for the lock overlay path.
  func forceSnapshot(size: CGSize, reason: String) {
    guard size.width > 0, size.height > 0 else { return }
    currentSize = size
    renderTimer?.invalidate()
    renderTimer = nil
    Task { @MainActor in
      await self.renderSnapshot(size: size, reason: reason)
    }
  }

  private func attachOffscreen(_ view: ARView, size: CGSize) {
    _ = attachOffscreenARViewToWindow(view, size: size)
  }

  private func renderSnapshot(size: CGSize, reason: String) async {
    // Create a temporary ARView sized to match
    let view = ARView(frame: CGRect(origin: .zero, size: size))
    // Use transparent background so snapshot composites cleanly over the ellipse
    view.environment.background = .color(.clear)
    prepareARViewForSnapshot(view)

    attachOffscreen(view, size: size)

    // Add camera with custom FOV (matching live view)
    let cameraAnchor = AnchorEntity(world: .zero)
    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = breakerSwitchFOV
    cameraAnchor.addChild(camera)
    view.scene.addAnchor(cameraAnchor)

    // Add lighting
    let lightAnchor = AnchorEntity(world: .zero)
    let directionalLight = DirectionalLight()
    directionalLight.light.intensity = 3000
    directionalLight.look(at: [0, 0, 0], from: [0, 2, 1], relativeTo: nil)
    lightAnchor.addChild(directionalLight)
    let ambientLight = PointLight()
    ambientLight.light.intensity = 1000
    ambientLight.position = [0, 0, 0]
    lightAnchor.addChild(ambientLight)
    view.scene.addAnchor(lightAnchor)

    // Load model - use a clone so the live view doesn't steal our entity mid-snapshot
    do {
      let sourceEntity = try await BreakerModelCache.shared.loadModel()
      let entity = sourceEntity.clone(recursive: true)
      entity.position = breakerSwitchPosition
      entity.scale = [breakerSwitchScale, breakerSwitchScale, breakerSwitchScale]
      entity.stopAllAnimations(recursive: true)

      // Set lever to locked position (down = 180°)
      if let lever = findLeverEntity(in: entity) {
        lever.transform.rotation = simd_quatf(angle: .pi, axis: [1, 0, 0])
      }

      let anchor = AnchorEntity(world: .zero)
      anchor.addChild(entity)
      view.scene.addAnchor(anchor)

      // Wait for render to complete (need a few frames)
      try? await Task.sleep(for: realityKitSnapshotWarmupDelay())

      // Snapshot
      view.snapshot(saveToHDR: false) { [weak self] image in
        Task { @MainActor in
          // Remove from hierarchy
          view.removeFromSuperview()

          if let image {
            self?.snapshot = image
            Log.debug(
              "BreakerSwitch",
              "✓ Snapshot captured (\(reason)) at \(Int(size.width))x\(Int(size.height))"
            )
          } else {
            Log.warn("BreakerSwitch", "⚠️ ARView.snapshot() returned nil")
          }
        }
      }
    } catch {
      Log.error("BreakerSwitch", "Snapshot render failed: \(error)")
      view.removeFromSuperview()
    }
  }
}

// MARK: - Model Cache

/// Lever sub-entity names to search for (model may use different naming)
private let leverEntityNames = ["lever", "Lever", "handle", "Handle", "arm", "Arm"]

/// Finds the lever sub-entity in a breaker model by searching known names.
private func findLeverEntity(in entity: Entity) -> Entity? {
  for name in leverEntityNames {
    if let lever = entity.findEntity(named: name) {
      return lever
    }
  }
  return nil
}

/// Caches the loaded Entity to avoid re-parsing USDZ on each view instance.
/// Reuses the same entity instance - RealityKit should orphan it when the view disappears.
private actor BreakerModelCache {
  static let shared = BreakerModelCache()

  private var cachedEntity: Entity?
  private var loadTask: Task<Entity, Error>?

  func loadModel() async throws -> Entity {
    // Return cached model if available (no clone - reuse directly)
    // Note: Entity may have stale parent ref, but adding to new content auto-reparents
    if let cached = cachedEntity {
      DebugBuild.run {
        // Avoid touching `Entity.parent` here: it's main-actor isolated and not worth the log complexity.
        Log.debug("BreakerSwitch", "ℹ️ Reusing cached entity")
      }
      return cached
    }

    // Coalesce concurrent loads
    if let task = loadTask {
      return try await task.value
    }

    // Start new load
    let task = Task<Entity, Error> {
      let entity = try await Entity(named: "breaker")
      return entity
    }
    loadTask = task

    do {
      let entity = try await task.value
      cachedEntity = entity
      loadTask = nil
      return entity
    } catch {
      loadTask = nil
      throw error
    }
  }
}

// MARK: - View

struct BreakerSwitchView: View {
  /// 0.0 = down/locked, 1.0 = up/unlocked
  var progress: CGFloat = 0.0

  @State private var leverEntity: Entity?

  var body: some View {
    RealityView { content in
      // Add camera with custom FOV for handle swing headroom
      let camera = PerspectiveCamera()
      camera.camera.fieldOfViewInDegrees = breakerSwitchFOV
      content.add(camera)

      // Add lighting
      let lightAnchor = Entity()
      let directionalLight = DirectionalLight()
      directionalLight.light.intensity = 3000
      directionalLight.look(at: [0, 0, 0], from: [0, 2, 1], relativeTo: nil)
      lightAnchor.addChild(directionalLight)
      let ambientLight = PointLight()
      ambientLight.light.intensity = 1000
      ambientLight.position = [0, 0, 0]
      lightAnchor.addChild(ambientLight)
      content.add(lightAnchor)

      // Load the breaker switch model (from cache)
      do {
        let entity = try await BreakerModelCache.shared.loadModel()

        // Position for viewing (virtual camera at origin looking at -Z)
        entity.position = breakerSwitchPosition
        entity.scale = [breakerSwitchScale, breakerSwitchScale, breakerSwitchScale]

        // Stop any baked animations
        entity.stopAllAnimations(recursive: true)

        content.add(entity)

        // Find lever sub-entity for animation
        if let lever = findLeverEntity(in: entity) {
          // Initialize to locked position (down = 180°)
          lever.transform.rotation = simd_quatf(angle: .pi, axis: [1, 0, 0])
          leverEntity = lever
        }
      } catch {
        Log.error("BreakerSwitch", "Failed to load model: \(error)")
        // Fallback: red box
        let mesh = MeshResource.generateBox(size: 0.3)
        let material = SimpleMaterial(color: .red, isMetallic: false)
        let box = ModelEntity(mesh: mesh, materials: [material])
        box.position = [0, 0, -1]
        content.add(box)
      }
    } update: { content in
      // Animate lever based on progress
      guard let lever = leverEntity else { return }

      // 0.0 = down (180°), 1.0 = up (0°)
      let angle = Float(1.0 - progress) * .pi
      lever.transform.rotation = simd_quatf(angle: angle, axis: [1, 0, 0])
    }
  }
}

// MARK: - Frustum Validation (kept for potential future use)

extension BreakerSwitchView {
  /// Validates that a model's bounding box is within reasonable viewing range.
  /// Returns nil if valid, or an error message describing the problem.
  static func validateFrustum(
    bounds: BoundingBox,
    cameraPosition: SIMD3<Float>,
    modelName: String
  ) -> String? {
    let size = bounds.max - bounds.min
    let maxDimension = max(size.x, size.y, size.z)

    if maxDimension < 0.001 {
      return "MODEL TOO SMALL: '\(modelName)' - \(maxDimension)m. Apply scale in Blender."
    }
    if maxDimension > 100 {
      return "MODEL TOO LARGE: '\(modelName)' - \(maxDimension)m. Apply scale in Blender."
    }

    let boundsCenter = (bounds.min + bounds.max) / 2
    let distanceToCamera = length(boundsCenter - cameraPosition)

    if distanceToCamera > 50 {
      return "MODEL TOO FAR: '\(modelName)' - \(distanceToCamera)m from camera."
    }
    if bounds.min.z > cameraPosition.z {
      return "MODEL BEHIND CAMERA: '\(modelName)' - Z=\(bounds.min.z) (needs negative Z)."
    }

    Log.debug("BreakerSwitch", "✓ Frustum OK: size=\(size), distance=\(distanceToCamera)m")
    return nil
  }
}

// MARK: - Preview

#Preview("Static States") {
  ZStack {
    Color.white.ignoresSafeArea()

    VStack(spacing: 40) {
      VStack(spacing: 8) {
        Text("Locked (progress = 0.0)")
          .foregroundColor(.black)
          .font(.caption)
        BreakerSwitchView(progress: 0.0)
          .frame(width: 200, height: 200)
          .border(Color.gray)
      }

      VStack(spacing: 8) {
        Text("Unlocked (progress = 1.0)")
          .foregroundColor(.black)
          .font(.caption)
        BreakerSwitchView(progress: 1.0)
          .frame(width: 200, height: 200)
          .border(Color.gray)
      }
    }
  }
}

#Preview("Interactive") {
  struct InteractiveSwitchPreview: View {
    @State private var progress: CGFloat = 0.0

    var body: some View {
      ZStack {
        Color.white.ignoresSafeArea()

        VStack(spacing: 30) {
          BreakerSwitchView(progress: progress)
            .frame(width: 250, height: 250)
            .border(Color.gray)

          VStack(spacing: 12) {
            Text("Progress: \(Int(progress * 100))%")
              .foregroundColor(.black)
              .font(.title2)
              .monospacedDigit()

            Slider(value: $progress, in: 0...1)
              .padding(.horizontal, 40)
          }
        }
      }
    }
  }

  return InteractiveSwitchPreview()
}
