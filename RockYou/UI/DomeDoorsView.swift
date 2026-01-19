// DomeDoorsView.swift
// RockYou
//
// 3D "emergency dome doors" over the DPad.
// Uses a procedural iris mask mapped onto the dome surface.

import CoreGraphics
import Foundation
import RealityKit
import SwiftUI

struct DomeDoorsView: View {
  /// 0 = closed dome, 1 = fully opened (doors moved away)
  var openProgress: CGFloat

  var backdropOpacity: CGFloat = CGFloat(DomeSceneConfig.defaultBackdropOpacity)
  var showDebugAxes: Bool = false
  var backdropScale: Float = DomeSceneConfig.defaultBackdropScale
  var backdropYawRadians: Float = DomeSceneConfig.defaultBackdropYawRadians
  var renderSurface: DomeRenderSurface = .dome
  /// Optional debug override for the camera orbit.
  var debugCameraOrbit: DomeDebugCameraOrbit? = nil

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var surfaceEntity: ModelEntity?
  @State private var lastMaskKey: DomeMaskKey?

  var body: some View {
    RealityView { content in
      // Camera (fixed during validation)
      let camAnchor = AnchorEntity(world: .zero)
      let cam = PerspectiveCamera()
      cam.camera.fieldOfViewInDegrees = DomeSceneConfig.cameraFovDegrees

      let orbit =
        debugCameraOrbit
        ?? DomeDebugCameraOrbit(
          yawDegrees: DomeSceneConfig.cameraYawDegrees,
          pitchDegrees: DomeSceneConfig.cameraPitchDegrees,
          distance: DomeSceneConfig.cameraDistance
        )

      let yawRadians = orbit.yawDegrees * .pi / 180
      let pitchRadians = orbit.pitchDegrees * .pi / 180
      let distance = max(0.1, orbit.distance)

      let x = sin(yawRadians) * cos(pitchRadians) * distance
      let z = cos(yawRadians) * cos(pitchRadians) * distance
      let y = sin(pitchRadians) * distance

      cam.position = [x, y, z]
      cam.look(at: .zero, from: cam.position, relativeTo: camAnchor)

      camAnchor.addChild(cam)
      content.add(camAnchor)
      camera = cam
      cameraAnchor = camAnchor

      // Lights (simple)
      let lightAnchor = AnchorEntity(world: .zero)
      let key = DirectionalLight()
      key.light.intensity = 2600
      key.look(at: .zero, from: [0.55, 1.0, -0.55], relativeTo: nil)
      lightAnchor.addChild(key)

      let fill = PointLight()
      fill.light.intensity = 520
      fill.position = [0.25, 0.25, -0.15]
      lightAnchor.addChild(fill)
      content.add(lightAnchor)

      // Backdrop
      if let backdrop = makeRefractedBackdropEntity(opacity: Float(backdropOpacity)) {
        backdrop.position = [0, -0.01, 0]
        backdrop.scale = [backdropScale, 1, backdropScale]
        backdrop.transform.rotation = simd_quatf(angle: backdropYawRadians, axis: [0, 1, 0])
        content.add(backdrop)
      }

      if showDebugAxes, let axes = makeDebugAxesAlways() {
        content.add(axes)
      }

      // Surface: dome or flat plane with iris mask as debug color.
      do {
        let mesh: MeshResource
        switch renderSurface {
        case .dome:
          mesh = try makeDomeMesh(radius: DomeSceneConfig.domeRadius)
        case .flat:
          mesh = MeshResource.generatePlane(
            width: DomeSceneConfig.backdropSize,
            depth: DomeSceneConfig.backdropSize
          )
        }

        let tRaw = Float(min(1, max(0, openProgress)))

        let material = makeDomeMaskMaterial(
          t: tRaw,
          bladeCount: DomeSceneConfig.bladeCount,
          config: DomeSceneConfig.irisConfig,
          textureSize: DomeSceneConfig.maskTextureSize
        )

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = [0, 0.01, 0]
        content.add(entity)

        surfaceEntity = entity
        lastMaskKey = DomeMaskKey(
          tBucket: DomeMaskKey.bucket(for: tRaw),
          bladeCount: DomeSceneConfig.bladeCount,
          textureSize: DomeSceneConfig.maskTextureSize
        )
      } catch {
        Log.error("DomeDoors", "Failed to build dome entities: \(error)")
      }
    } update: { _ in
      if let camera, let cameraAnchor, let orbit = debugCameraOrbit {
        let yawRadians = orbit.yawDegrees * .pi / 180
        let pitchRadians = orbit.pitchDegrees * .pi / 180
        let distance = max(0.1, orbit.distance)
        let x = sin(yawRadians) * cos(pitchRadians) * distance
        let z = cos(yawRadians) * cos(pitchRadians) * distance
        let y = sin(pitchRadians) * distance
        camera.position = [x, y, z]
        camera.look(at: .zero, from: camera.position, relativeTo: cameraAnchor)
      }

      guard let surfaceEntity else { return }

      let tRaw = Float(min(1, max(0, openProgress)))

      let key = DomeMaskKey(
        tBucket: DomeMaskKey.bucket(for: tRaw),
        bladeCount: DomeSceneConfig.bladeCount,
        textureSize: DomeSceneConfig.maskTextureSize
      )
      guard key != lastMaskKey else { return }

      let material = makeDomeMaskMaterial(
        t: tRaw,
        bladeCount: DomeSceneConfig.bladeCount,
        config: DomeSceneConfig.irisConfig,
        textureSize: DomeSceneConfig.maskTextureSize
      )

      surfaceEntity.model?.materials = [material]
      lastMaskKey = key
    }
    .allowsHitTesting(false)
    .id(renderSurface)
  }
}

private struct DomeMaskKey: Equatable {
  let tBucket: Int
  let bladeCount: Int
  let textureSize: Int

  static func bucket(for t: Float) -> Int {
    Int((DomeIrisAnimation.clamp(t) * 1000).rounded())
  }
}

struct DomeDebugCameraOrbit {
  var yawDegrees: Float
  var pitchDegrees: Float
  var distance: Float
}

enum DomeRenderSurface: Hashable {
  case dome
  case flat
}

@MainActor
private func makeRefractedBackdropEntity(opacity: Float) -> ModelEntity? {
  guard let path = Bundle.main.path(forResource: "DPad-Refracted", ofType: "png"),
    let native = PlatformImage.cachedNativeContentsOfFile(path),
    let cg = PlatformImage.cgImage(from: native)
  else {
    DebugBuild.run { Log.warn("DomeDoors", "Missing DPad-Refracted.png for dome backdrop") }
    return nil
  }

  let tex: TextureResource
  do {
    tex = try TextureResource(
      image: cg, withName: "DPad-Refracted", options: .init(semantic: .color))
  } catch {
    Log.error("DomeDoors", "TextureResource(image:) failed: \(error)")
    return nil
  }

  let mesh = MeshResource.generatePlane(
    width: DomeSceneConfig.backdropSize,
    depth: DomeSceneConfig.backdropSize
  )
  var mat = UnlitMaterial()
  mat.color = .init(texture: .init(tex))
  mat.blending = .transparent(opacity: .init(floatLiteral: opacity))
  mat.opacityThreshold = 0.02
  mat.faceCulling = .none

  return ModelEntity(mesh: mesh, materials: [mat])
}

enum DomeSceneConfig {
  static let refractedOverscan: Float = 1.00
  static let baseDomeRadius: Float = 0.5
  static let domeRadius: Float = baseDomeRadius / refractedOverscan
  static let backdropSize: Float = baseDomeRadius * 2

  /// Used by LockableDPadView to size the dome render canvas relative to the DPad.
  static let renderCanvasScale: Float = 1.25

  /// Base pixel size used by RockYouApp+macOS to compute render backing size.
  /// This is a UI/layout constant, not part of the iris math.
  static let dpadRenderSize: Float = 520

  static let bladeCount: Int = 6
  static let defaultBackdropOpacity: Float = 1.0
  static let defaultBackdropScale: Float = 1.0
  static let defaultBackdropYawRadians: Float = 0
  static let maskTextureSize: Int = 512

  static let cameraFovDegrees: Float = 50
  static let cameraYawDegrees: Float = 0
  static let cameraPitchDegrees: Float = 50
  static let cameraDistance: Float = 1.25

  static let irisConfig: DomeIrisConfig = .default
}

/// Creates XYZ axis visualization at origin (RGB = XYZ).
private func makeDebugAxesAlways() -> Entity? {
  let container = Entity()
  let axisLength: Float = 0.5
  let axisRadius: Float = 0.005
  let labelOffset: Float = 0.08

  let xAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .red, isMetallic: false)]
  )
  xAxis.position = [axisLength / 2, 0, 0]
  xAxis.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
  container.addChild(xAxis)

  let xLabel = ModelEntity(
    mesh: .generateText("X", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .red, isMetallic: false)]
  )
  xLabel.position = [axisLength + labelOffset, 0, 0]
  container.addChild(xLabel)

  let yAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .green, isMetallic: false)]
  )
  yAxis.position = [0, axisLength / 2, 0]
  container.addChild(yAxis)

  let yLabel = ModelEntity(
    mesh: .generateText("Y", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .green, isMetallic: false)]
  )
  yLabel.position = [0, axisLength + labelOffset, 0]
  container.addChild(yLabel)

  let zAxis = ModelEntity(
    mesh: .generateCylinder(height: axisLength, radius: axisRadius),
    materials: [SimpleMaterial(color: .blue, isMetallic: false)]
  )
  zAxis.position = [0, 0, axisLength / 2]
  zAxis.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
  container.addChild(zAxis)

  let zLabel = ModelEntity(
    mesh: .generateText("Z", extrusionDepth: 0.01, font: .systemFont(ofSize: 0.1)),
    materials: [SimpleMaterial(color: .blue, isMetallic: false)]
  )
  zLabel.position = [0, 0, axisLength + labelOffset]
  container.addChild(zLabel)

  return container
}

/// Hemisphere mesh used for the dome surface.
private func makeDomeMesh(radius: Float) throws -> MeshResource {
  let thetaSegments = 22
  let phiSegments = 96

  var positions: [SIMD3<Float>] = []
  var normals: [SIMD3<Float>] = []
  var uvs: [SIMD2<Float>] = []
  positions.reserveCapacity((thetaSegments + 1) * (phiSegments + 1))
  normals.reserveCapacity((thetaSegments + 1) * (phiSegments + 1))
  uvs.reserveCapacity((thetaSegments + 1) * (phiSegments + 1))

  for j in 0...phiSegments {
    let u = Float(j) / Float(phiSegments)
    let phi = u * (2 * .pi)
    for i in 0...thetaSegments {
      let tt = Float(i) / Float(thetaSegments)
      let theta = tt * (.pi / 2)
      let sinTheta = sin(theta)
      let cosTheta = cos(theta)

      let x = radius * sinTheta * cos(phi)
      let z = radius * sinTheta * sin(phi)
      let y = radius * cosTheta

      let p = SIMD3<Float>(x, y, z)
      let n = simd_normalize(p)
      positions.append(p)
      normals.append(n)
      uvs.append(makeMaskUV(for: n))
    }
  }

  var indices: [UInt32] = []
  indices.reserveCapacity(thetaSegments * phiSegments * 6)
  let stride = thetaSegments + 1
  for j in 0..<phiSegments {
    for i in 0..<thetaSegments {
      let a = UInt32(j * stride + i)
      let b = UInt32((j + 1) * stride + i)
      let c = UInt32((j + 1) * stride + (i + 1))
      let d = UInt32(j * stride + (i + 1))
      indices.append(contentsOf: [a, b, d, b, c, d])
    }
  }

  var desc = MeshDescriptor()
  desc.positions = MeshBuffers.Positions(positions)
  desc.normals = MeshBuffers.Normals(normals)
  desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
  desc.primitives = .triangles(indices)

  return try MeshResource.generate(from: [desc])
}

/// Object-space spherical mapping to mask UVs (centered on +Y axis).
private func makeMaskUV(for normal: SIMD3<Float>) -> SIMD2<Float> {
  let n = simd_normalize(normal)
  let theta = atan2(n.z, n.x)
  let y = min(1, max(-1, n.y))
  let rho = acos(y)
  let r = rho / (.pi / 2)
  let p = SIMD2<Float>(r * cos(theta), r * sin(theta))
  return SIMD2<Float>(p.x * 0.5 + 0.5, p.y * 0.5 + 0.5)
}

private func makeDomeMaskMaterial(
  t: Float,
  bladeCount: Int,
  config: DomeIrisConfig,
  textureSize: Int
) -> RealityKit.Material {
  var material = UnlitMaterial()
  if let texture = makeIrisMaskTexture(
    t: t,
    bladeCount: bladeCount,
    config: config,
    textureSize: textureSize
  ) {
    material.color = .init(texture: .init(texture))
  }
  material.blending = .transparent(opacity: 1.0)
  material.faceCulling = .back
  return material
}

private func makeIrisMaskTexture(
  t: Float,
  bladeCount: Int,
  config: DomeIrisConfig,
  textureSize: Int
) -> TextureResource? {
  guard
    let cg = DomeIrisMaskRenderer.makeMaskImage(
      size: textureSize,
      t: t,
      bladeCount: bladeCount,
      config: config
    )
  else { return nil }

  do {
    return try TextureResource(
      image: cg, withName: "Dome-Iris-Mask", options: .init(semantic: .color))
  } catch {
    Log.error("DomeDoors", "TextureResource(image:) failed: \(error)")
    return nil
  }
}
