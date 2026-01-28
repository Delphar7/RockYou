// IrisContent.swift
// RockYou/UI/Dome
//
// Iris mechanism content for SceneView.
// Creates a tessellated dome with iris blade animation driven by time.

import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

private let irisLog = Logger(subsystem: "com.rockyou", category: "IrisContent")

/// Iris mechanism content - a tessellated dome with animated blade opening.
@MainActor
final class IrisContent: SceneContent {
  let config: IrisAnimationConfig
  let entity: Entity

  private let domeEntity: ModelEntity
  private let ribbonEntity: ModelEntity?
  private var dataTexture: TextureResource?

  init(config: IrisAnimationConfig) {
    self.config = config

    // Create root entity
    let root = Entity()

    // Generate dome mesh
    guard let meshGenerator = DomeMeshGenerator(),
          let mesh = meshGenerator.generateMesh(
            latSegments: Self.latSegments(for: config.fragmentCount),
            lonSegments: Self.lonSegments(for: config.fragmentCount),
            radius: config.domeRadius
          ) else {
      irisLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      return
    }

    // Create data texture for shader params
    guard let texture = Self.createDataTexture(config: config) else {
      irisLog.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      return
    }
    self.dataTexture = texture

    // Create material with iris shaders
    guard let material = Self.createIrisMaterial(texture: texture) else {
      irisLog.error("Failed to create iris material")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.ribbonEntity = nil
      return
    }

    // Create dome entity
    let dome = ModelEntity(mesh: mesh, materials: [material])
    root.addChild(dome)
    self.domeEntity = dome

    // Create seam ribbon entity if enabled
    if config.showSeamRibbons {
      if let ribbonMesh = Self.createSeamRibbonMesh(bladeCount: config.bladeCount),
         let ribbonMaterial = Self.createSeamRibbonMaterial(texture: texture) {
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
    // Update dome material uniforms
    if var material = domeEntity.model?.materials.first as? CustomMaterial {
      material.custom.value = [time, cameraPosition.x, cameraPosition.y, cameraPosition.z]
      domeEntity.model?.materials = [material]
    }

    // Update ribbon material uniforms
    if let ribbon = ribbonEntity,
       var material = ribbon.model?.materials.first as? CustomMaterial {
      material.custom.value = [time, cameraPosition.x, cameraPosition.y, cameraPosition.z]
      ribbon.model?.materials = [material]
    }
  }

  // MARK: - Mesh Generation Helpers

  private static func latSegments(for fragmentCount: Int) -> Int {
    let segments = max(4, Int(sqrt(Double(fragmentCount))))
    return segments / 2
  }

  private static func lonSegments(for fragmentCount: Int) -> Int {
    return max(4, Int(sqrt(Double(fragmentCount))))
  }

  // MARK: - Material Creation

  private static func createIrisMaterial(texture: TextureResource) -> CustomMaterial? {
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

      material.faceCulling = .none  // Double-sided for glass/metal effect
      material.custom.value = [0, 0, 0, 0]  // [time, camX, camY, camZ]
      material.custom.texture = .init(texture)

      return material
    } catch {
      irisLog.error("Failed to create iris material: \(error)")
      return nil
    }
  }

  private static func createSeamRibbonMaterial(texture: TextureResource) -> CustomMaterial? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return nil
    }

    do {
      let geometryModifier = CustomMaterial.GeometryModifier(
        named: "irisSeamRibbonGeometryModifier",
        in: library
      )
      let surfaceShader = CustomMaterial.SurfaceShader(
        named: "irisSeamRibbonSurfaceShader",
        in: library
      )

      var material = try CustomMaterial(
        surfaceShader: surfaceShader,
        geometryModifier: geometryModifier,
        lightingModel: .lit
      )

      material.faceCulling = .none
      material.custom.value = [0, 0, 0, 0]
      material.custom.texture = .init(texture)

      return material
    } catch {
      irisLog.error("Failed to create ribbon material: \(error)")
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

        // Two triangles for quad
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
      irisLog.error("Failed to generate ribbon mesh: \(error)")
      return nil
    }
  }

  // MARK: - Data Texture

  private static let textureWidth = 32
  private static let textureHeight = 4096

  private static func createDataTexture(config: IrisAnimationConfig) -> TextureResource? {
    let width = textureWidth
    let height = textureHeight

    let latSegs = latSegments(for: config.fragmentCount)
    let lonSegs = lonSegments(for: config.fragmentCount)

    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)

    for rowIdx in 0..<height {
      // Cols 0-2: Lookup table data (random values for physics - iris doesn't use these much)
      // Col 0: velocity placeholder
      pixels.append(contentsOf: [128, 128, 128, 128])
      // Col 1: angular velocity placeholder
      pixels.append(contentsOf: [128, 128, 128, 128])
      // Col 2: rotation quaternion placeholder
      pixels.append(contentsOf: [128, 128, 128, 128])

      if rowIdx == 0 {
        // Header row with dome/iris params

        // Col 3: radius (RG), latSegments (BA)
        let radius16 = encode16bit(config.domeRadius, min: 0.0, max: 2.0)
        let latSegs16 = UInt16(clamping: latSegs)
        pixels.append(UInt8((radius16 >> 8) & 0xFF))
        pixels.append(UInt8(radius16 & 0xFF))
        pixels.append(UInt8((latSegs16 >> 8) & 0xFF))
        pixels.append(UInt8(latSegs16 & 0xFF))

        // Col 4: lonSegments (RG), waveSpeed (BA) - unused for iris
        let lonSegs16 = UInt16(clamping: lonSegs)
        pixels.append(UInt8((lonSegs16 >> 8) & 0xFF))
        pixels.append(UInt8(lonSegs16 & 0xFF))
        pixels.append(contentsOf: [0, 0])

        // Col 5-6: wave origin (unused for iris)
        pixels.append(contentsOf: [128, 128, 128, 128])
        pixels.append(contentsOf: [128, 128, 0, 0])

        // Col 7: Algorithm ID (3 = iris)
        pixels.append(3)  // iris algorithm
        pixels.append(contentsOf: [0, 0, 0])

        // Col 8-11: Physics config (baseSpeed stores radius for iris)
        let baseSpeed16 = encode16bit(config.domeRadius, min: -2.0, max: 2.0)
        pixels.append(contentsOf: [128, 128, 128, 128])  // col 8
        pixels.append(contentsOf: [128, 128, 128, 128])  // col 9
        pixels.append(UInt8((baseSpeed16 >> 8) & 0xFF))  // col 10: baseSpeed
        pixels.append(UInt8(baseSpeed16 & 0xFF))
        pixels.append(contentsOf: [128, 128])
        pixels.append(contentsOf: [128, 128, 128, 128])  // col 11

        // Col 12-13: Ripple params (unused for iris)
        pixels.append(contentsOf: [128, 128, 128, 128])
        pixels.append(contentsOf: [128, 128, 128, 128])

        // Col 14: irisBladeCount (RG), irisOpenDuration (BA)
        let blades16 = UInt16(clamping: config.bladeCount)
        let duration16 = encode16bit(config.openDuration, min: 0.1, max: 10.0)
        pixels.append(UInt8((blades16 >> 8) & 0xFF))
        pixels.append(UInt8(blades16 & 0xFF))
        pixels.append(UInt8((duration16 >> 8) & 0xFF))
        pixels.append(UInt8(duration16 & 0xFF))

        // Col 15: reserved (RG), irisTwist (BA)
        let twist16 = encode16bit(config.twistDegrees, min: -180.0, max: 180.0)
        pixels.append(128)
        pixels.append(128)
        pixels.append(UInt8((twist16 >> 8) & 0xFF))
        pixels.append(UInt8(twist16 & 0xFF))

        // Remaining cols: padding
        for _ in 16..<width {
          pixels.append(contentsOf: [128, 128, 128, 128])
        }
      } else {
        // Non-header rows: padding
        for _ in 3..<width {
          pixels.append(contentsOf: [128, 128, 128, 128])
        }
      }
    }

    // Create CGImage from pixel data
    let bytesPerRow = width * 4
    let nsData = Data(pixels)
    guard let provider = CGDataProvider(data: nsData as CFData) else {
      irisLog.error("CGDataProvider creation failed")
      return nil
    }

    // Use LINEAR color space to avoid gamma correction mangling our encoded data
    guard let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
          let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: linearColorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
      irisLog.error("CGImage creation failed")
      return nil
    }

    do {
      return try TextureResource(image: cgImage, withName: "IrisData", options: .init(semantic: .raw))
    } catch {
      irisLog.error("Failed to create texture: \(error)")
      return nil
    }
  }

  // MARK: - Encoding Helpers

  private static func encode16bit(_ value: Float, min: Float, max: Float) -> UInt16 {
    let normalized = (value - min) / (max - min)
    let clamped = Swift.max(0, Swift.min(1, normalized))
    return UInt16(clamped * 65535)
  }
}
