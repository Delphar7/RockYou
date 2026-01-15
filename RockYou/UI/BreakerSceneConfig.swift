//
//  BreakerSceneConfig.swift
//  RockYou
//
//  Shared scene configuration for the 3D breaker switch.
//  Used by both BreakerSwitchView (live) and BreakerSwitchSnapshotManager (static).
//

import RealityKit
import SwiftUI

// MARK: - Scene Configuration

/// Centralized config for breaker 3D scene setup.
enum BreakerSceneConfig {
  /// Model scale factor (1.0 = no scaling)
  static let scale: Float = 1.1

  /// Model position in world space (at origin)
  static let position: SIMD3<Float> = [0, 0, 0]

  /// Camera distance from origin
  static let cameraDistance: Float = 1.0

  /// Camera field of view in degrees (wider = more headroom for handle swing)
  static let cameraFOV: Float = 75

  /// Camera yaw around Y axis in degrees - positive = rotate left (counterclockwise from above)
  /// Range: 0° (front view) to 60° (angled view)
  static let cameraYawDegrees: Float = 10

  /// Directional light intensity (key light)
  static let directionalLightIntensity: Float = 3000

  /// Point light intensity (fill/ambient)
  static let pointLightIntensity: Float = 100

  /// Lever sub-entity names to search for (model may use different naming)
  static let leverEntityNames = [
    "Cylinder002", "Cylinder", "lever", "Lever", "handle", "Handle", "arm", "Arm",
  ]

  /// Lever rotation angle when locked/down (radians).
  static let leverLockedAngle: Float = 0

  /// Lever rotation angle when unlocked/up (radians).
  static let leverUnlockedAngle: Float = -150 * .pi / 180  // -150°

  /// Lever rotation axis (try [1,0,0] for X, [0,1,0] for Y, [0,0,1] for Z)
  static let leverRotationAxis: SIMD3<Float> = [1, 0, 0]

  /// Unlock drag camera yaw: max additional orbit in degrees applied over progress 0→1.
  static let unlockCameraYawMaxDegrees: Float = 45

  /// If the yaw direction feels “backwards”, flip this between +1 and -1.
  static let unlockCameraYawSlopeFlipSign: Float = -1

  /// Debug: Show XYZ axes at origin and make model transparent (DEBUG builds only)
  static let showDebugAxes: Bool = {
    #if DEBUG && false
      return true
    #else
      return false
    #endif
  }()

  /// Computes lever rotation angle for a given progress (0.0 = locked, 1.0 = unlocked)
  static func computeLeverAngle(progress: CGFloat) -> Float {
    let locked = leverLockedAngle
    let unlocked = leverUnlockedAngle
    return locked + Float(progress) * (unlocked - locked)
  }
}

// MARK: - Debug Helpers

/// Creates XYZ axis visualization at world origin (RGB = XYZ).
/// Returns nil if debug axes are disabled.
func makeDebugAxes() -> Entity? {
  guard BreakerSceneConfig.showDebugAxes else { return nil }

  let container = Entity()
  let axisLength: Float = 0.5
  let axisRadius: Float = 0.005
  let labelOffset: Float = 0.08  // Distance beyond axis end for label

  // X axis = Red
  let xAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .red, isMetallic: false)]
  )
  xAxis.position = [axisLength / 2, 0, 0]
  xAxis.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])  // Rotate to point along X
  container.addChild(xAxis)

  // X label
  let xLabel = ModelEntity(
    mesh: .generateText("X", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .red, isMetallic: false)]
  )
  xLabel.position = [axisLength + labelOffset, 0, 0]
  container.addChild(xLabel)

  // Y axis = Green
  let yAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .green, isMetallic: false)]
  )
  yAxis.position = [0, axisLength / 2, 0]
  container.addChild(yAxis)

  // Y label
  let yLabel = ModelEntity(
    mesh: .generateText("Y", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .green, isMetallic: false)]
  )
  yLabel.position = [0, axisLength + labelOffset, 0]
  container.addChild(yLabel)

  // Z axis = Blue
  let zAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .blue, isMetallic: false)]
  )
  zAxis.position = [0, 0, axisLength / 2]
  zAxis.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])  // Rotate to point along Z
  container.addChild(zAxis)

  // Z label
  let zLabel = ModelEntity(
    mesh: .generateText("Z", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .blue, isMetallic: false)]
  )
  zLabel.position = [0, 0, axisLength + labelOffset]
  container.addChild(zLabel)

  return container
}

// MARK: - Shared Rig Builders

/// Creates a camera anchor configured for the breaker scene.
/// The camera orbits around the Y axis at the configured yaw angle and distance.
func makeBreakerCameraAnchor() -> AnchorEntity {
  let cameraAnchor = AnchorEntity(world: .zero)
  let camera = PerspectiveCamera()
  camera.camera.fieldOfViewInDegrees = BreakerSceneConfig.cameraFOV

  // Position camera in orbit around origin at specified yaw angle
  let yawRadians = BreakerSceneConfig.cameraYawDegrees * .pi / 180
  let distance = BreakerSceneConfig.cameraDistance
  camera.position = [
    sin(yawRadians) * distance,  // X: positive = right
    0,  // Y: stays on horizontal plane
    cos(yawRadians) * distance,  // Z: positive = towards camera
  ]

  // Point camera at model (at origin)
  camera.look(at: BreakerSceneConfig.position, from: camera.position, relativeTo: cameraAnchor)

  cameraAnchor.addChild(camera)
  return cameraAnchor
}

/// Creates a light anchor with directional + point lights for the breaker scene.
func makeBreakerLightAnchor() -> AnchorEntity {
  let lightAnchor = AnchorEntity(world: .zero)

  let directionalLight = DirectionalLight()
  directionalLight.light.intensity = BreakerSceneConfig.directionalLightIntensity
  directionalLight.look(at: [0, 0, 0], from: [0, 2, 1], relativeTo: nil)
  lightAnchor.addChild(directionalLight)

  let ambientLight = PointLight()
  ambientLight.light.intensity = BreakerSceneConfig.pointLightIntensity
  ambientLight.position = [0, 0, 0]
  lightAnchor.addChild(ambientLight)

  return lightAnchor
}

/// Finds the lever sub-entity in a breaker model by searching known names.
func findLeverEntity(in entity: Entity) -> Entity? {
  for name in BreakerSceneConfig.leverEntityNames {
    if let lever = entity.findEntity(named: name) {
      return lever
    }
  }
  return nil
}

/// Validates the model contains only geometry (ModelComponents).
/// Returns error message if non-model entities found, nil if clean.
@MainActor
func validateBreakerModelIsClean(_ entity: Entity) -> String? {
  var nonModelEntities: [String] = []

  // Check if entity or any descendant has a ModelComponent
  func hasModelInTree(_ e: Entity) -> Bool {
    if e.components.has(ModelComponent.self) {
      return true
    }
    return e.children.contains { hasModelInTree($0) }
  }

  func checkRecursive(_ e: Entity, isRoot: Bool = false) {
    // Root entity and container entities are OK if they have model descendants
    if !isRoot {
      let hasModel = e.components.has(ModelComponent.self)
      let hasModelDescendants = e.children.contains { hasModelInTree($0)   }

      if !hasModel && !hasModelDescendants {
        nonModelEntities.append(e.name)
      }
    }

    for child in e.children {
      checkRecursive(child, isRoot: false)
    }
  }

  checkRecursive(entity, isRoot: true)

  guard nonModelEntities.isEmpty else {
    return """
      USDZ model contains non-geometry entities (likely lights/cameras from Blender)!

      Found: \(nonModelEntities.joined(separator: ", "))

      Re-export the model with ONLY the base and lever geometry.
      No lights, cameras, or other scene objects.
      """
  }
  return nil
}

/// Applies consistent display setup for a breaker model entity (position/scale, stop animations, lever init).
/// Returns the lever entity if found.
@MainActor
func prepareBreakerEntityForDisplay(_ entity: Entity) -> Entity? {
  // Position model at origin
  entity.position = BreakerSceneConfig.position
  let s = BreakerSceneConfig.scale
  entity.scale = [s, s, s]

  // Stop any baked animations
  entity.stopAllAnimations(recursive: true)

  // Debug: Make model transparent to see axes
  if BreakerSceneConfig.showDebugAxes {
    entity.components.set(OpacityComponent(opacity: 0.25))
  }

  // Initialize lever to locked position
  if let lever = findLeverEntity(in: entity) {
    let angle = BreakerSceneConfig.computeLeverAngle(progress: 0.0)
    lever.transform.rotation = simd_quatf(
      angle: angle, axis: BreakerSceneConfig.leverRotationAxis)
    return lever
  }

  return nil
}
