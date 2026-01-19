// DomeDoorsView.swift
// RockYou
//
// 3D "emergency dome doors" over the DPad.
// Uses a procedural iris mask mapped onto the dome surface.

import CoreGraphics
import Foundation
import Metal
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

  // Debug: 3D reference plane showing the actual DPad for size comparison
  var showDPadReferencePlane: Bool = false
  var dpadReferencePlaneAbove: Bool = true
  var dpadReferencePlaneOpacity: Float = 0.5

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var surfaceEntity: ModelEntity?
  @State private var dpadReferenceEntity: ModelEntity?
  @State private var lastMaskKey: DomeMaskKey?

  var body: some View {
    GeometryReader { _ in
      RealityView { content in
        // Camera: animated based on openProgress (or debug override)
        let camAnchor = AnchorEntity(world: .zero)
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = DomeSceneConfig.cameraFovDegrees

        // Initial camera position based on current progress
        if let orbit = debugCameraOrbit {
          // Debug override
          let yawRadians = orbit.yawDegrees * .pi / 180
          let pitchRadians = orbit.pitchDegrees * .pi / 180
          let distance = max(0.1, orbit.distance)
          let x = sin(yawRadians) * cos(pitchRadians) * distance
          let z = cos(yawRadians) * cos(pitchRadians) * distance
          let y = sin(pitchRadians) * distance
          cam.position = [x, y, z]
        } else {
          // Animated position based on progress
          cam.position = cameraPositionForProgress(Float(openProgress))
        }
        cam.look(at: .zero, from: cam.position, relativeTo: camAnchor)

        camAnchor.addChild(cam)
        content.add(camAnchor)
        camera = cam
        cameraAnchor = camAnchor

        // Lights: key light positioned to match app's implied lighting
        // (~45° elevation, ~30° to the right, toward viewer)
        let lightAnchor = AnchorEntity(world: .zero)
        let key = DirectionalLight()
        key.light.intensity = 2600
        key.look(at: .zero, from: [0.8, 0.6, 0.5], relativeTo: nil)
        lightAnchor.addChild(key)

        let fill = PointLight()
        fill.light.intensity = 520
        fill.position = [0.4, 0.3, 0.2]
        lightAnchor.addChild(fill)
        content.add(lightAnchor)

        // Backdrop plane disabled - DPad textures now composited directly in surface shader
        // if let backdrop = makeRefractedBackdropEntity(opacity: Float(backdropOpacity)) {
        //   backdrop.position = [0, -0.01, 0]
        //   backdrop.scale = [backdropScale, 1, backdropScale]
        //   backdrop.transform.rotation = simd_quatf(angle: backdropYawRadians, axis: [0, 1, 0])
        //   content.add(backdrop)
        // }

        if showDebugAxes, let axes = makeDebugAxesAlways() {
          content.add(axes)
        }

        // Debug: 3D reference plane showing actual DPad for size comparison
        if showDPadReferencePlane,
          let refPlane = makeDPadReferenceEntity(opacity: dpadReferencePlaneOpacity)
        {
          let yOffset: Float = dpadReferencePlaneAbove ? 0.02 : -0.02
          refPlane.position = [0, yOffset, 0]
          // Match the backdrop scale
          refPlane.scale = [backdropScale, 1, backdropScale]
          content.add(refPlane)
          dpadReferenceEntity = refPlane
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
            textureSize: DomeSceneConfig.maskTextureSize,
            cameraPosition: cam.position
          )

          let entity = ModelEntity(mesh: mesh, materials: [material])
          entity.position = [0, 0.01, 0]

          // Scale dome to fit within the ellipse (match ellipse height)
          let s = DomeSceneConfig.domeEntityScale
          entity.scale = [s, s, s]

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
        // Update camera position based on progress (or debug override)
        if let camera, let cameraAnchor {
          if let orbit = debugCameraOrbit {
            // Debug override
            let yawRadians = orbit.yawDegrees * .pi / 180
            let pitchRadians = orbit.pitchDegrees * .pi / 180
            let distance = max(0.1, orbit.distance)
            let x = sin(yawRadians) * cos(pitchRadians) * distance
            let z = cos(yawRadians) * cos(pitchRadians) * distance
            let y = sin(pitchRadians) * distance
            camera.position = [x, y, z]
          } else {
            // Animated position based on progress
            camera.position = cameraPositionForProgress(Float(openProgress))
          }
          camera.look(at: .zero, from: camera.position, relativeTo: cameraAnchor)
        }

        guard let surfaceEntity else { return }

        let tRaw = Float(min(1, max(0, openProgress)))

        // Check if we need to update the mask texture (t changed)
        let key = DomeMaskKey(
          tBucket: DomeMaskKey.bucket(for: tRaw),
          bladeCount: DomeSceneConfig.bladeCount,
          textureSize: DomeSceneConfig.maskTextureSize
        )
        // Always update material to pass current camera position for parallax
        guard key != lastMaskKey else { return }

        // Get current camera position for ray-plane intersection
        let camPos = camera?.position ?? cameraPositionForProgress(Float(openProgress))

        let material = makeDomeMaskMaterial(
          t: tRaw,
          bladeCount: DomeSceneConfig.bladeCount,
          config: DomeSceneConfig.irisConfig,
          textureSize: DomeSceneConfig.maskTextureSize,
          cameraPosition: camPos
        )

        surfaceEntity.model?.materials = [material]
        lastMaskKey = key
      }
      .allowsHitTesting(false)
    }
    .id("\(renderSurface)-\(showDPadReferencePlane)-\(dpadReferencePlaneAbove)")
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

/// Computes camera position for a given progress (0=closed, 1=open).
/// Orbits from startYaw by orbitDegrees while lifting from startPitch to endPitch.
private func cameraPositionForProgress(_ progress: Float) -> SIMD3<Float> {
  let t = min(1, max(0, progress))

  // Yaw: linear, but reversed direction (subtract instead of add)
  let yawDegrees = DomeSceneConfig.cameraStartYawDegrees - DomeSceneConfig.cameraOrbitDegrees * t

  // Pitch: ease-in (t²) so lift accelerates toward the end
  let tEased = t * t
  let pitchDegrees = DomeSceneConfig.cameraStartPitchDegrees +
    (DomeSceneConfig.cameraEndPitchDegrees - DomeSceneConfig.cameraStartPitchDegrees) * tEased

  let yawRadians = yawDegrees * .pi / 180
  let pitchRadians = pitchDegrees * .pi / 180
  let distance = DomeSceneConfig.cameraDistance

  let x = sin(yawRadians) * cos(pitchRadians) * distance
  let z = cos(yawRadians) * cos(pitchRadians) * distance
  let y = sin(pitchRadians) * distance

  return [x, y, z]
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

/// Creates backdrop plane with regular (non-refracted) DPad texture.
/// This shows through the aperture opening.
@MainActor
private func makeRegularBackdropEntity(opacity: Float) -> ModelEntity? {
  guard let path = Bundle.main.path(forResource: "DPad-Regular", ofType: "png"),
    let native = PlatformImage.cachedNativeContentsOfFile(path),
    let cg = PlatformImage.cgImage(from: native)
  else {
    DebugBuild.run { Log.warn("DomeDoors", "Missing DPad-Regular.png for dome backdrop") }
    return nil
  }

  let tex: TextureResource
  do {
    tex = try TextureResource(
      image: cg, withName: "DPad-Regular", options: .init(semantic: .color))
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

/// Creates a 3D plane showing the DPad ring image for size comparison.
@MainActor
private func makeDPadReferenceEntity(opacity: Float) -> ModelEntity? {
  // Use DPad-Ring.png as reference (the actual DPad's ring component)
  guard let path = Bundle.main.path(forResource: "DPad-Ring", ofType: "png"),
    let native = PlatformImage.cachedNativeContentsOfFile(path),
    let cg = PlatformImage.cgImage(from: native)
  else {
    Log.warn("DomeDoors", "Missing DPad-Ring.png for reference plane")
    return nil
  }

  let tex: TextureResource
  do {
    tex = try TextureResource(
      image: cg, withName: "DPad-Reference", options: .init(semantic: .color))
  } catch {
    Log.error("DomeDoors", "TextureResource for DPad reference failed: \(error)")
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

  /// Ellipse height scale (from LockableDPadView: dpadSize * 1.1)
  static let ellipseHeightScale: Float = 1.24

  /// Scale factor for dome entity to fit within ellipse
  static let domeEntityScale: Float = ellipseHeightScale / renderCanvasScale

  /// Base pixel size used by RockYouApp+macOS to compute render backing size.
  /// This is a UI/layout constant, not part of the iris math.
  static let dpadRenderSize: Float = 520

  static let bladeCount: Int = 9
  static let defaultBackdropOpacity: Float = 1.0
  static let defaultBackdropScale: Float = 1.0
  static let defaultBackdropYawRadians: Float = 0
  static let maskTextureSize: Int = 2048

  static let cameraFovDegrees: Float = 50

  // Camera animation: orbits 180° while lifting from angled to top-down
  static let cameraStartYawDegrees: Float = 180    // Starting yaw (progress=0)
  static let cameraOrbitDegrees: Float = 180       // Amount to orbit during animation
  static let cameraStartPitchDegrees: Float = 45   // Starting pitch (angled view)
  static let cameraEndPitchDegrees: Float = 90     // Ending pitch (straight down)
  static let cameraDistance: Float = 1.25          // Constant distance from center

  // Glass material properties
  static let glassRoughness: Float = 0.08
  static let glassClearcoat: Float = 0.5
  static let glassClearcoatRoughness: Float = 0.03

  /// Use GPU compute shader for mask generation (vs CPU fallback)
  static let useGPU: Bool = true

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

/// Cached Metal library for custom material shader
private var cachedMetalLibrary: MTLLibrary?

@MainActor
private func makeDomeMaskMaterial(
  t: Float,
  bladeCount: Int,
  config: DomeIrisConfig,
  textureSize: Int,
  cameraPosition: SIMD3<Float>
) -> RealityKit.Material {
  guard let maskTexture = makeIrisGlassTexture(
    t: t,
    bladeCount: bladeCount,
    config: config,
    textureSize: textureSize
  ) else {
    // Fallback to solid gray if texture fails
    var fallback = PhysicallyBasedMaterial()
    fallback.baseColor = .init(tint: .init(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.35))
    return fallback
  }

  // Try CustomMaterial for per-pixel ray-traced DPad blending
  if let customMaterial = makeCustomGlassMaterial(
    maskTexture: maskTexture,
    cameraPosition: cameraPosition,
    backdropSize: DomeSceneConfig.backdropSize
  ) {
    return customMaterial
  }

  // Fallback to PhysicallyBasedMaterial if CustomMaterial fails
  return makePBRGlassMaterial(texture: maskTexture)
}

/// Cached DPad textures for screen-space sampling
private var cachedRegularDPadTexture: TextureResource?
private var cachedRefractedDPadTexture: TextureResource?

@MainActor
private func loadDPadTextures() -> (regular: TextureResource, refracted: TextureResource)? {
  // Return cached if available
  if let regular = cachedRegularDPadTexture, let refracted = cachedRefractedDPadTexture {
    return (regular, refracted)
  }

  // Load regular DPad texture
  guard let regularPath = Bundle.main.path(forResource: "DPad-Regular", ofType: "png"),
    let regularNative = PlatformImage.cachedNativeContentsOfFile(regularPath),
    let regularCG = PlatformImage.cgImage(from: regularNative)
  else {
    Log.warn("DomeDoors", "Missing DPad-Regular.png")
    return nil
  }

  // Load refracted DPad texture
  guard let refractedPath = Bundle.main.path(forResource: "DPad-Refracted", ofType: "png"),
    let refractedNative = PlatformImage.cachedNativeContentsOfFile(refractedPath),
    let refractedCG = PlatformImage.cgImage(from: refractedNative)
  else {
    Log.warn("DomeDoors", "Missing DPad-Refracted.png")
    return nil
  }

  do {
    let regularTex = try TextureResource(
      image: regularCG, withName: "DPad-Regular-Shader", options: .init(semantic: .color))
    let refractedTex = try TextureResource(
      image: refractedCG, withName: "DPad-Refracted-Shader", options: .init(semantic: .color))
    cachedRegularDPadTexture = regularTex
    cachedRefractedDPadTexture = refractedTex
    return (regularTex, refractedTex)
  } catch {
    Log.error("DomeDoors", "Failed to create DPad textures: \(error)")
    return nil
  }
}

@MainActor
private func makeCustomGlassMaterial(
  maskTexture: TextureResource,
  cameraPosition: SIMD3<Float>,
  backdropSize: Float
) -> CustomMaterial? {
  do {
    // Get or create Metal library
    let library: MTLLibrary
    if let cached = cachedMetalLibrary {
      library = cached
    } else {
      guard let device = MTLCreateSystemDefaultDevice() else {
        Log.warn("DomeDoors", "No Metal device available")
        return nil
      }
      library = try device.makeDefaultLibrary(bundle: .main)
      cachedMetalLibrary = library
    }

    // Load DPad textures for screen-space sampling
    guard let dpadTextures = loadDPadTextures() else {
      Log.warn("DomeDoors", "Failed to load DPad textures")
      return nil
    }

    // Create surface shader
    let surfaceShader = CustomMaterial.SurfaceShader(
      named: "domeSurfaceShader",
      in: library
    )

    // Create custom material with clearcoat lighting model
    var material = try CustomMaterial(
      surfaceShader: surfaceShader,
      lightingModel: .clearcoat
    )

    // Pass textures to shader:
    // - custom: iris glass mask (dome UV mapping)
    // - baseColor: regular DPad (shown through aperture)
    // - emissiveColor: refracted DPad (shown through glass)
    material.custom.texture = .init(maskTexture)
    material.baseColor.texture = .init(dpadTextures.regular)
    material.emissiveColor.texture = .init(dpadTextures.refracted)

    // Pass camera position (xyz) + backdrop size (w) for ray-plane intersection
    material.custom.value = [
      cameraPosition.x,
      cameraPosition.y,
      cameraPosition.z,
      backdropSize
    ]

    // Enable transparency
    material.blending = .transparent(opacity: 1.0)
    material.faceCulling = .back

    return material
  } catch {
    Log.warn("DomeDoors", "CustomMaterial creation failed: \(error)")
    return nil
  }
}

private func makePBRGlassMaterial(texture: TextureResource) -> PhysicallyBasedMaterial {
  var material = PhysicallyBasedMaterial()

  // Base color from RGBA texture (tint + alpha baked in)
  material.baseColor = .init(tint: .white, texture: .init(texture))

  // Low roughness for glossy glass-like specular reflections
  material.roughness = .init(floatLiteral: DomeSceneConfig.glassRoughness)

  // Glass is dielectric (non-metallic)
  material.metallic = .init(floatLiteral: 0.0)

  // Clearcoat for extra glossy layer
  material.clearcoat = .init(floatLiteral: DomeSceneConfig.glassClearcoat)
  material.clearcoatRoughness = .init(floatLiteral: DomeSceneConfig.glassClearcoatRoughness)

  // Transparent blending using texture alpha
  material.blending = .transparent(opacity: .init(floatLiteral: 1.0))

  // Back-face culling
  material.faceCulling = .back

  return material
}

private func makeIrisGlassTexture(
  t: Float,
  bladeCount: Int,
  config: DomeIrisConfig,
  textureSize: Int
) -> TextureResource? {
  // Choose GPU or CPU renderer
  let cg: CGImage?
  if DomeSceneConfig.useGPU {
    cg = DomeGPURenderer.makeGlassMaskImage(
      size: textureSize,
      t: t,
      bladeCount: bladeCount,
      config: config
    )
  } else {
    cg = DomeIrisMaskRenderer.makeGlassMaskImage(
      size: textureSize,
      t: t,
      bladeCount: bladeCount,
      config: config
    )
  }

  guard let cgImage = cg else { return nil }

  do {
    return try TextureResource(
      image: cgImage, withName: "Dome-Iris-Glass", options: .init(semantic: .color))
  } catch {
    Log.error("DomeDoors", "TextureResource(image:) failed: \(error)")
    return nil
  }
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
