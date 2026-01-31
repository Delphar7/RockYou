// FlowerContent.swift
// RockYou/UI/Dome
//
// Blooming flower content for SceneView.
// Iris blades on a dome that rotate open like a flower.
// Uses DomeBladeMeshGenerator for mesh creation; animation is pivot rotation.

import RealityKit
import simd

/// Blooming flower scene content - iris blades that open on a dome.
/// Extracted from BloomingFlowerRealityView for the SceneContent pipeline.
@MainActor
final class FlowerContent: SceneContent {
  let config: FlowerAnimationConfig
  let entity: Entity

  private let bladeAnchors: [Entity]
  private let maxRotationRadians: Float = 1.5
  private var lastTime: Float = 0

  var isComplete: Bool { lastTime >= config.openDuration }

  init(config: FlowerAnimationConfig) {
    self.config = config

    let root = Entity()

    let meshConfig = DomeBladeMeshConfig(
      bladeCount: config.bladeCount,
      domeRadius: config.domeRadius,
      bladeCoverage: config.bladeCoverage,
      bladeOverlap: config.bladeOverlap
    )

    let glassMaterial = DomeBladeMeshGenerator.makeGlassMaterial()
    let metalMaterial = DomeBladeMeshGenerator.makeMetalMaterial()

    let N = max(3, config.bladeCount)
    let sectorAngle = (2 * Float.pi) / Float(N)
    var anchors: [Entity] = []

    for i in 0..<N {
      let baseAngle = Float(i) * sectorAngle

      let pivotAnchor = Entity()
      pivotAnchor.name = "BladePivot_\(i)"

      let pivotTheta = Float.pi / 2
      let pivotPhi = baseAngle
      let r = config.domeRadius
      let pivotPos = SIMD3<Float>(
        r * sin(pivotTheta) * cos(pivotPhi),
        r * cos(pivotTheta),
        r * sin(pivotTheta) * sin(pivotPhi)
      )
      pivotAnchor.position = pivotPos

      do {
        let mesh = try DomeBladeMeshGenerator.makeBladeSurfaceMesh(bladeIndex: i, config: meshConfig)

        let glassEntity = ModelEntity(mesh: mesh, materials: [glassMaterial])
        glassEntity.name = "Blade_\(i)_glass"
        glassEntity.position = -pivotPos

        let metalEntity = ModelEntity(mesh: mesh, materials: [metalMaterial])
        metalEntity.name = "Blade_\(i)_metal"
        metalEntity.position = -pivotPos

        pivotAnchor.addChild(glassEntity)
        pivotAnchor.addChild(metalEntity)
      } catch {
        // Skip this blade if mesh generation fails
      }

      root.addChild(pivotAnchor)
      anchors.append(pivotAnchor)
    }

    self.entity = root
    self.bladeAnchors = anchors
  }

  func update(time: Float, cameraPosition: SIMD3<Float>) {
    let N = bladeAnchors.count
    guard N > 0 else { return }

    lastTime = time

    // Map time to aperture: 0 at t=0, 1 at t=openDuration
    let aperture = min(1.0, time / config.openDuration)
    let t = aperture * aperture * (3 - 2 * aperture)  // smoothstep

    let sectorAngle = (2 * Float.pi) / Float(N)

    for (i, pivotAnchor) in bladeAnchors.enumerated() {
      let baseAngle = Float(i) * sectorAngle
      let axisAngle = baseAngle + Float.pi / 2
      let axis = SIMD3<Float>(cos(axisAngle), 0, sin(axisAngle))
      let rotation = -t * maxRotationRadians

      pivotAnchor.orientation = simd_quatf(angle: rotation, axis: axis)
    }
  }
}
