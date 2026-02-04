// IrisContent.swift
// RockYou/UI/Dome
//
// Iris mechanism content for SceneView.
// Uses dot(Q, n_i) > threshold for blade coverage with tilted plane normals.
// Spiral seams via tilt parameter.

import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

private let log = Logger(subsystem: "com.rockyou", category: "IrisContent")

/// Iris content - blade coverage via plane half-space checks.
/// Seam arcs are plane-sphere intersection circles with general basis vectors.
@MainActor
final class IrisContent: SceneContent {
  let config: IrisAnimationConfig
  let entity: Entity

  /// SceneContent protocol - animation complete when all fragments invisible (iris open)
  var isComplete: Bool { visibilityTracker.allFragmentsGone }

  private let domeEntity: ModelEntity
  private let ribbonEntity: ModelEntity?
  private var dataTexture: TextureResource?
  private var mtlDataTexture: MTLTexture?  // Raw Metal texture for compute shader
  private let fragmentCount: Int
  private let visibilityTracker = VisibilityTracker()

  init(config: IrisAnimationConfig) {
    self.config = config

    let root = Entity()

    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    // Generate dome mesh
    guard let meshGenerator = DomeMeshGenerator(),
          let mesh = meshGenerator.generateMesh(
            latSegments: latSegs,
            lonSegments: lonSegs,
            radius: config.domeRadius
          ) else {
      log.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      self.fragmentCount = 0
      return
    }

    self.fragmentCount = DomeMeshGenerator.fragmentCount(latSegments: latSegs, lonSegments: lonSegs)

    // Create data texture for shader params (also creates MTLTexture for compute)
    let textureResult = Self.createDataTexture(config: config)
    guard let texture = textureResult.resource else {
      log.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      return
    }
    self.dataTexture = texture
    self.mtlDataTexture = textureResult.mtlTexture

    // Create material with iris shaders
    guard let material = Self.createDomeMaterial(texture: texture) else {
      log.error("Failed to create dome material")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      return
    }

    let dome = ModelEntity(mesh: mesh, materials: [material])
    root.addChild(dome)
    self.domeEntity = dome

    // Create seam ribbon entity if enabled
    if config.showSeamRibbons {
      if let ribbonMesh = Self.createSeamRibbonMesh(bladeCount: config.bladeCount),
         let ribbonMaterial = Self.createSeamMaterial(texture: texture) {
        let ribbon = ModelEntity(mesh: ribbonMesh, materials: [ribbonMaterial])
        root.addChild(ribbon)
        self.ribbonEntity = ribbon
      } else {
        self.ribbonEntity = nil
      }
    } else {
      self.ribbonEntity = nil
    }

    self.entity = root
  }

  func update(time: Float, cameraPosition: SIMD3<Float>) {
    if var material = domeEntity.model?.materials.first as? CustomMaterial {
      material.custom.value = [time, cameraPosition.x, cameraPosition.y, cameraPosition.z]
      domeEntity.model?.materials = [material]
    }

    if let ribbon = ribbonEntity,
       var material = ribbon.model?.materials.first as? CustomMaterial {
      material.custom.value = [time, cameraPosition.x, cameraPosition.y, cameraPosition.z]
      ribbon.model?.materials = [material]
    }

    checkVisibility(at: time)
  }

  // MARK: - Visibility Checking

  private func checkVisibility(at time: Float) {
    guard let mtlTexture = mtlDataTexture else { return }
    visibilityTracker.checkIfNeeded(
      at: time,
      animation: IrisVisibilityAdapter(texture: mtlTexture, fragmentCount: fragmentCount)
    ) {
      log.info("All fragments gone (iris fully open) at t=\(time)")
    }
  }

  // MARK: - Material Creation

  private static func createDomeMaterial(texture: TextureResource) -> CustomMaterial? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return nil
    }

    do {
      let geometryModifier = CustomMaterial.GeometryModifier(
        named: "irisGeometryModifier",
        in: library
      )
      let surfaceShader = CustomMaterial.SurfaceShader(
        named: "irisSurfaceShader",
        in: library
      )

      var material = try CustomMaterial(
        surfaceShader: surfaceShader,
        geometryModifier: geometryModifier,
        lightingModel: .lit
      )

      material.faceCulling = .none
      material.blending = .transparent(opacity: .init(floatLiteral: 1.0))  // Let shader control opacity
      material.custom.value = [0, 0, 0, 0]
      material.custom.texture = .init(texture)

      return material
    } catch {
      log.error("Failed to create dome material: \(error)")
      return nil
    }
  }

  private static func createSeamMaterial(texture: TextureResource) -> CustomMaterial? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return nil
    }

    do {
      let geometryModifier = CustomMaterial.GeometryModifier(
        named: "irisSeamGeometryModifier",
        in: library
      )
      let surfaceShader = CustomMaterial.SurfaceShader(
        named: "irisSeamSurfaceShader",
        in: library
      )

      var material = try CustomMaterial(
        surfaceShader: surfaceShader,
        geometryModifier: geometryModifier,
        lightingModel: .lit
      )

      material.faceCulling = .none
      material.blending = .transparent(opacity: 1.0)
      material.custom.value = [0, 0, 0, 0]
      material.custom.texture = .init(texture)

      return material
    } catch {
      log.error("Failed to create seam material: \(error)")
      return nil
    }
  }

  // MARK: - Seam Ribbon Mesh

  private static func createSeamRibbonMesh(bladeCount: Int, segmentsPerArc: Int = 32) -> MeshResource? {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    for blade in 0..<bladeCount {
      let bladeF = Float(blade)

      for seg in 0..<segmentsPerArc {
        let t0 = Float(seg) / Float(segmentsPerArc)
        let t1 = Float(seg + 1) / Float(segmentsPerArc)
        let baseIdx = UInt32(positions.count)

        // Vertex 0: t0, left edge
        positions.append(SIMD3<Float>(0, 0, 0))
        normals.append(SIMD3<Float>(0, 1, 0))
        uvs.append(SIMD2<Float>(t0, bladeF + 0.0))

        // Vertex 1: t0, right edge
        positions.append(SIMD3<Float>(0, 0, 0))
        normals.append(SIMD3<Float>(0, 1, 0))
        uvs.append(SIMD2<Float>(t0, bladeF + 0.5))

        // Vertex 2: t1, left edge
        positions.append(SIMD3<Float>(0, 0, 0))
        normals.append(SIMD3<Float>(0, 1, 0))
        uvs.append(SIMD2<Float>(t1, bladeF + 0.0))

        // Vertex 3: t1, right edge
        positions.append(SIMD3<Float>(0, 0, 0))
        normals.append(SIMD3<Float>(0, 1, 0))
        uvs.append(SIMD2<Float>(t1, bladeF + 0.5))

        indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
        indices.append(contentsOf: [baseIdx + 2, baseIdx + 1, baseIdx + 3])
      }
    }

    var desc = MeshDescriptor(name: "iris_seam_ribbons")
    desc.positions = MeshBuffers.Positions(positions)
    desc.normals = MeshBuffers.Normals(normals)
    desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
    desc.primitives = .triangles(indices)

    do {
      return try MeshResource.generate(from: [desc])
    } catch {
      log.error("Failed to generate ribbon mesh: \(error)")
      return nil
    }
  }

  // MARK: - Data Texture

  private static func createDataTexture(config: IrisAnimationConfig) -> TextureParamWriter.TextureResult {
    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    var params = TextureParamWriter()

    // Shared dome params
    params.writeFloat16(config.domeRadius, at: TextureParam.radius, min: 0.0, max: 2.0)
    params.writeInt16(latSegs, at: TextureParam.latSegments)
    params.writeInt16(lonSegs, at: TextureParam.lonSegments)

    // Algorithm ID
    params.writeInt16(5, at: TextureParam.algorithmID)

    // baseSpeed stores domeRadius (used by iris for radius lookup in physics config path)
    params.writeFloat16(config.domeRadius, at: TextureParam.baseSpeed, min: -2.0, max: 2.0)

    // Iris-specific params
    params.writeInt16(config.bladeCount, at: TextureParam.bladeCount)
    params.writeFloat16(config.openDuration, at: TextureParam.openDuration, min: 0.1, max: 10.0)
    params.writeFloat16(config.tilt, at: TextureParam.tilt, min: 0.0, max: Float.pi / 2)
    params.writeFloat16(config.elevation, at: TextureParam.elevation, min: 0.0, max: Float.pi / 4)

    return params.createTexture(name: "IrisData")
  }
}

// MARK: - Visibility Adapter

/// Adapter to make IrisContent work with VisibilityChecker
private struct IrisVisibilityAdapter: VisibilityCheckable {
  let texture: MTLTexture
  let fragmentCount: Int

  var visibilityKernelName: String { "irisVisibilityKernel" }

  func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder) {
    // Buffer 2: fragment count (buffer 0 = anyVisible, buffer 1 = time)
    var count = UInt32(fragmentCount)
    encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

    // Texture 0: data texture
    encoder.setTexture(texture, index: 0)
  }
}
