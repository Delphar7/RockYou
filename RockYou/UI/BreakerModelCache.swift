//
//  BreakerModelCache.swift
//  RockYou
//
//  Caches the breaker 3D model Entity to avoid re-parsing USDZ on each view instance.
//

import RealityKit

/// Caches the parsed breaker USDZ as a **template** and vends a fresh clone to each caller.
///
/// Ownership rule (defense-in-depth): the cached `templateEntity` is never added to a scene
/// and never mutated by display code. Every renderer — the live `BreakerSwitchView` and the
/// offscreen snapshot `ARView` — gets its own `makeInstance()` clone. This prevents the same
/// `Entity` from being parented into two scenes at once, and stops one renderer's display
/// setup (transforms, `stopAllAnimations`, components) from mutating an entity another
/// renderer is reading. Clones still share immutable GPU `MeshResource`/material buffers,
/// which is safe for read-only rendering; the hazard we close here is shared *Entity* state.
// `Entity` (and `clone(recursive:)`) are MainActor-isolated, so the cache that holds and
// clones them is MainActor-isolated too. All callers (the live RealityView closure and the
// @MainActor snapshot manager) already run on the main actor.
@MainActor
final class BreakerModelCache {
  static let shared = BreakerModelCache()

  private var templateEntity: Entity?
  private var loadTask: Task<Entity, Error>?

  /// Returns a fresh clone of the breaker model, safe to add to a scene and mutate.
  /// Callers must use this rather than rendering a shared instance.
  func makeInstance() async throws -> Entity {
    let template = try await loadTemplate()
    return template.clone(recursive: true)
  }

  /// Loads (and caches) the immutable template entity. Coalesces concurrent loads.
  /// The returned entity is the shared template — do not add it to a scene directly.
  private func loadTemplate() async throws -> Entity {
    if let cached = templateEntity {
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
      templateEntity = entity
      loadTask = nil
      return entity
    } catch {
      loadTask = nil
      throw error
    }
  }
}
