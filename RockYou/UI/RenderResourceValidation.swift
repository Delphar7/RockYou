//
//  RenderResourceValidation.swift
//  RockYou
//
//  Validation gate for GPU-bound resources before they are handed to RealityKit.
//
//  Defense-in-depth: a malformed mesh (non-finite or inverted bounds) handed to the
//  render engine can surface as a render-thread crash deep inside CoreRE, with no
//  app frames on the crashing stack. Validating at the producer keeps the failure
//  local and diagnosable. Fail-clean: a non-nil result means "do not render this";
//  callers should drop the resource rather than attach it to a live scene.
//

import RealityKit
import simd

enum RenderResourceValidation {

  /// Validates a `MeshResource` has finite, non-inverted bounds.
  /// Returns nil when valid, or a human-readable reason when not.
  static func validate(mesh: MeshResource, label: String) -> String? {
    validate(bounds: mesh.bounds, label: "MeshResource(\(label))")
  }

  /// Validates a bounding box is finite and not inverted.
  ///
  /// Note: zero-volume bounds are intentionally allowed — some meshes (e.g. the iris
  /// seam ribbon) ship degenerate geometry that a geometry modifier expands on the GPU.
  /// Only non-finite (NaN/Inf) and inverted (min > max) bounds indicate corruption.
  static func validate(bounds: BoundingBox, label: String) -> String? {
    let mn = bounds.min
    let mx = bounds.max
    let comps = [mn.x, mn.y, mn.z, mx.x, mx.y, mx.z]
    if comps.contains(where: { !$0.isFinite }) {
      return "\(label): non-finite bounds (min=\(mn), max=\(mx))"
    }
    if mx.x < mn.x || mx.y < mn.y || mx.z < mn.z {
      return "\(label): inverted bounds (min=\(mn), max=\(mx))"
    }
    return nil
  }

  /// Validates an entity tree: every `ModelComponent` mesh must have finite, non-inverted bounds.
  /// Returns nil when the whole tree is valid, or the first problem found.
  @MainActor
  static func validate(entity: Entity, label: String) -> String? {
    if let model = entity.components[ModelComponent.self] {
      if let reason = validate(mesh: model.mesh, label: "\(label)/\(entity.name)") {
        return reason
      }
    }
    for child in entity.children {
      if let reason = validate(entity: child, label: label) {
        return reason
      }
    }
    return nil
  }
}
