// DPadBackdrop.swift
// RockYou/UI/Dome
//
// Shared helper for adding a DPad texture backdrop plane.

import Foundation
import RealityKit

enum DPadBackdrop {
  static func makeEntity(radius: Float, name: String) -> ModelEntity? {
    guard let path = Bundle.main.path(forResource: "DPad-Refracted", ofType: "png"),
          let native = PlatformImage.cachedNativeContentsOfFile(path),
          let cg = PlatformImage.cgImage(from: native) else {
      return nil
    }

    let tex: TextureResource
    do {
      tex = try TextureResource(
        image: cg,
        withName: name,
        options: .init(semantic: .color)
      )
    } catch {
      return nil
    }

    let mesh = MeshResource.generatePlane(width: radius * 2, depth: radius * 2)
    var mat = UnlitMaterial()
    mat.color = .init(texture: .init(tex))
    mat.blending = .transparent(opacity: 1.0)
    mat.opacityThreshold = 0.01

    let entity = ModelEntity(mesh: mesh, materials: [mat])
    entity.position = [0, -0.01, 0]  // Slightly below dome
    return entity
  }
}
