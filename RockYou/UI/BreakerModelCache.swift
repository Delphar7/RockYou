//
//  BreakerModelCache.swift
//  RockYou
//
//  Caches the breaker 3D model Entity to avoid re-parsing USDZ on each view instance.
//

import RealityKit

/// Caches the loaded Entity to avoid re-parsing USDZ on each view instance.
/// Reuses the same entity instance - RealityKit should orphan it when the view disappears.
actor BreakerModelCache {
  static let shared = BreakerModelCache()

  private var cachedEntity: Entity?
  private var loadTask: Task<Entity, Error>?

  func loadModel() async throws -> Entity {
    // Return cached model if available (no clone - reuse directly)
    // Note: Entity may have stale parent ref, but adding to new content auto-reparents
    if let cached = cachedEntity {
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
