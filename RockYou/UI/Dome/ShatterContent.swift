// ShatterContent.swift
// RockYou/UI/Dome
//
// Shatter (explode/confetti) content for SceneView.
// Creates a tessellated dome with physics-based fragment animation.

import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

private let shatterLog = Logger(subsystem: "com.rockyou", category: "ShatterContent")

/// Shatter content - a tessellated dome with explode or confetti physics.
@MainActor
final class ShatterContent: SceneContent {
  let config: ShatterAnimationConfig
  let entity: Entity

  private let domeEntity: ModelEntity
  private var dataTexture: TextureResource?

  init(config: ShatterAnimationConfig, cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]) {
    self.config = config

    // Create root entity
    let root = Entity()

    Log.debug("ShatterContent", "Init: mode=\(config.mode) fragments=\(config.fragmentCount) radius=\(config.domeRadius)")

    // Generate dome mesh
    guard let meshGenerator = DomeMeshGenerator() else {
      Log.warn("ShatterContent", "FAIL: DomeMeshGenerator init returned nil")
      shatterLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }

    let latSegs = Self.latSegments(for: config.fragmentCount)
    let lonSegs = Self.lonSegments(for: config.fragmentCount)
    Log.debug("ShatterContent", "Mesh gen: latSegs=\(latSegs) lonSegs=\(lonSegs)")

    guard let mesh = meshGenerator.generateMesh(
            latSegments: latSegs,
            lonSegments: lonSegs,
            radius: config.domeRadius
          ) else {
      Log.warn("ShatterContent", "FAIL: generateMesh returned nil")
      shatterLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    Log.debug("ShatterContent", "Mesh generated OK")

    // Compute wave origin from camera position if wave enabled
    let waveOrigin: SIMD3<Float>? = config.waveEnabled
      ? simd_normalize(cameraPosition) * config.domeRadius * 0.8
      : nil

    // Create data texture for shader params
    guard let texture = Self.createDataTexture(config: config, waveOrigin: waveOrigin) else {
      Log.warn("ShatterContent", "FAIL: createDataTexture returned nil")
      shatterLog.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    self.dataTexture = texture
    Log.debug("ShatterContent", "Data texture created OK")

    // Create material with appropriate shaders
    guard let material = Self.createMaterial(config: config, texture: texture) else {
      Log.warn("ShatterContent", "FAIL: createMaterial returned nil")
      shatterLog.error("Failed to create shatter material")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    Log.debug("ShatterContent", "Material created OK")

    // Create dome entity
    let dome = ModelEntity(mesh: mesh, materials: [material])
    root.addChild(dome)
    self.domeEntity = dome
    Log.debug("ShatterContent", "Init complete: entity has \(root.children.count) children")

    self.entity = root
  }

  func update(time: Float, cameraPosition: SIMD3<Float>) {
    // Update dome material uniforms
    if var material = domeEntity.model?.materials.first as? CustomMaterial {
      material.custom.value = [time, cameraPosition.x, cameraPosition.y, cameraPosition.z]
      domeEntity.model?.materials = [material]
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

  private static func createMaterial(config: ShatterAnimationConfig, texture: TextureResource) -> CustomMaterial? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return nil
    }

    // Select shaders based on mode
    let geometryName: String
    let surfaceName: String

    switch config.mode {
    case .explode:
      geometryName = "explodeGeometryModifier"
      surfaceName = "fragmentSurfaceShader"
    case .confetti:
      geometryName = "confettiGeometryModifier"
      surfaceName = "confettiSurfaceShader"
    }

    do {
      let geometryModifier = CustomMaterial.GeometryModifier(
        named: geometryName,
        in: library
      )
      let surfaceShader = CustomMaterial.SurfaceShader(
        named: surfaceName,
        in: library
      )

      var material = try CustomMaterial(
        surfaceShader: surfaceShader,
        geometryModifier: geometryModifier,
        lightingModel: .lit
      )

      material.faceCulling = .none  // Double-sided
      material.blending = .transparent(opacity: .init(floatLiteral: 1.0))  // Let shader control opacity
      material.custom.value = [0, 0, 0, 0]  // [time, camX, camY, camZ]
      material.custom.texture = .init(texture)

      return material
    } catch {
      shatterLog.error("Failed to create shatter material: \(error)")
      return nil
    }
  }

  // MARK: - Data Texture

  private static let textureWidth = 32
  private static let textureHeight = 4096

  private static func createDataTexture(
    config: ShatterAnimationConfig,
    waveOrigin: SIMD3<Float>?
  ) -> TextureResource? {
    let width = textureWidth
    let height = textureHeight

    let latSegs = latSegments(for: config.fragmentCount)
    let lonSegs = lonSegments(for: config.fragmentCount)

    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)

    for rowIdx in 0..<height {
      // Cols 0-2: Lookup table data (random physics values - used by shaders via stable_random)
      pixels.append(contentsOf: [128, 128, 128, 128])  // col 0
      pixels.append(contentsOf: [128, 128, 128, 128])  // col 1
      pixels.append(contentsOf: [128, 128, 128, 128])  // col 2

      if rowIdx == 0 {
        // Header row with dome/physics params

        // Col 3: radius (RG), latSegments (BA)
        let radius16 = encode16bit(config.domeRadius, min: 0.0, max: 2.0)
        let latSegs16 = UInt16(clamping: latSegs)
        pixels.append(UInt8((radius16 >> 8) & 0xFF))
        pixels.append(UInt8(radius16 & 0xFF))
        pixels.append(UInt8((latSegs16 >> 8) & 0xFF))
        pixels.append(UInt8(latSegs16 & 0xFF))

        // Col 4: lonSegments (RG), waveSpeed (BA)
        let lonSegs16 = UInt16(clamping: lonSegs)
        let waveSpeed16 = encode16bit(config.waveSpeed, min: 0.0, max: 10.0)
        pixels.append(UInt8((lonSegs16 >> 8) & 0xFF))
        pixels.append(UInt8(lonSegs16 & 0xFF))
        pixels.append(UInt8((waveSpeed16 >> 8) & 0xFF))
        pixels.append(UInt8(waveSpeed16 & 0xFF))

        // Col 5-6: wave origin
        if let origin = waveOrigin {
          let ox16 = encode16bit(origin.x, min: -2.0, max: 2.0)
          let oy16 = encode16bit(origin.y, min: -2.0, max: 2.0)
          let oz16 = encode16bit(origin.z, min: -2.0, max: 2.0)
          pixels.append(UInt8((ox16 >> 8) & 0xFF))
          pixels.append(UInt8(ox16 & 0xFF))
          pixels.append(UInt8((oy16 >> 8) & 0xFF))
          pixels.append(UInt8(oy16 & 0xFF))
          pixels.append(UInt8((oz16 >> 8) & 0xFF))
          pixels.append(UInt8(oz16 & 0xFF))
          pixels.append(1)  // wave enabled
          pixels.append(0)
        } else {
          pixels.append(contentsOf: [128, 128, 128, 128])  // col 5
          pixels.append(contentsOf: [128, 128, 0, 0])      // col 6: wave disabled
        }

        // Col 7: Algorithm ID (R), cannon power (GB)
        let algorithmID: UInt8 = config.mode == .explode ? 0 : 1
        let cannonPower16 = encode16bit(config.cannonPower, min: 0.0, max: 5.0)
        pixels.append(algorithmID)
        pixels.append(UInt8((cannonPower16 >> 8) & 0xFF))
        pixels.append(UInt8(cannonPower16 & 0xFF))
        pixels.append(0)

        // Col 8: baseGravity (RG), gravityMin (BA) - must match FragmentMath.h layout
        let baseGrav16 = encode16bit(config.baseGravity, min: 0.0, max: 2.0)
        let gravMin16 = encode16bit(config.gravityMin, min: 0.0, max: 2.0)
        pixels.append(UInt8((baseGrav16 >> 8) & 0xFF))
        pixels.append(UInt8(baseGrav16 & 0xFF))
        pixels.append(UInt8((gravMin16 >> 8) & 0xFF))
        pixels.append(UInt8(gravMin16 & 0xFF))

        // Col 9: gravityMax (RG), spinRateMin (BA)
        let gravMax16 = encode16bit(config.gravityMax, min: 0.0, max: 2.0)
        let spinMin16 = encode16bit(config.spinRateMin, min: 0.0, max: 20.0)
        pixels.append(UInt8((gravMax16 >> 8) & 0xFF))
        pixels.append(UInt8(gravMax16 & 0xFF))
        pixels.append(UInt8((spinMin16 >> 8) & 0xFF))
        pixels.append(UInt8(spinMin16 & 0xFF))

        // Col 10: spinRateMax (RG), baseSpeed (BA)
        let spinMax16 = encode16bit(config.spinRateMax, min: 0.0, max: 20.0)
        let baseSpeed16 = encode16bit(config.baseSpeed, min: -2.0, max: 2.0)
        pixels.append(UInt8((spinMax16 >> 8) & 0xFF))
        pixels.append(UInt8(spinMax16 & 0xFF))
        pixels.append(UInt8((baseSpeed16 >> 8) & 0xFF))
        pixels.append(UInt8(baseSpeed16 & 0xFF))

        // Col 11: spreadAngle (RG), upwardBias (BA)
        let spread16 = encode16bit(config.spreadAngle, min: 0.0, max: 2.0)
        let upward16 = encode16bit(config.upwardBias, min: -2.0, max: 2.0)
        pixels.append(UInt8((spread16 >> 8) & 0xFF))
        pixels.append(UInt8(spread16 & 0xFF))
        pixels.append(UInt8((upward16 >> 8) & 0xFF))
        pixels.append(UInt8(upward16 & 0xFF))

        // Cols 12-31: padding
        for _ in 12..<width {
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
      shatterLog.error("CGDataProvider creation failed")
      return nil
    }

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
      shatterLog.error("CGImage creation failed")
      return nil
    }

    do {
      return try TextureResource(image: cgImage, withName: "ShatterData", options: .init(semantic: .raw))
    } catch {
      shatterLog.error("Failed to create texture: \(error)")
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
