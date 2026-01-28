// RippleContent.swift
// RockYou/UI/Dome
//
// Ripple animation content for SceneView.
// Radial sin wave from impact point, fragments detach after N waves, then fall.

import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

private let rippleLog = Logger(subsystem: "com.rockyou", category: "RippleContent")

/// Ripple content - a tessellated dome with expanding wave animation.
@MainActor
final class RippleContent: SceneContent {
  let config: RippleAnimationConfig
  let entity: Entity

  private let domeEntity: ModelEntity
  private var dataTexture: TextureResource?

  init(config: RippleAnimationConfig, cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]) {
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
      rippleLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }

    // Compute wave origin: 45 degrees around Y from camera-facing point
    let cameraDir = simd_normalize(cameraPosition)
    let angle: Float = .pi / 4
    let rotatedDir = SIMD3<Float>(
      cameraDir.x * cos(angle) - cameraDir.z * sin(angle),
      cameraDir.y,
      cameraDir.x * sin(angle) + cameraDir.z * cos(angle)
    )
    let waveOrigin = rotatedDir * config.domeRadius * 0.8

    // Create data texture for shader params
    guard let texture = Self.createDataTexture(config: config, waveOrigin: waveOrigin) else {
      rippleLog.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    self.dataTexture = texture

    // Create material with ripple shaders
    guard let material = Self.createMaterial(texture: texture) else {
      rippleLog.error("Failed to create ripple material")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }

    // Create dome entity
    let dome = ModelEntity(mesh: mesh, materials: [material])
    root.addChild(dome)
    self.domeEntity = dome

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

  private static func createMaterial(texture: TextureResource) -> CustomMaterial? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return nil
    }

    do {
      let geometryModifier = CustomMaterial.GeometryModifier(
        named: "rippleGeometryModifier",
        in: library
      )
      let surfaceShader = CustomMaterial.SurfaceShader(
        named: "rippleSurfaceShader",
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
      rippleLog.error("Failed to create ripple material: \(error)")
      return nil
    }
  }

  // MARK: - Data Texture

  private static let textureWidth = 32
  private static let textureHeight = 4096

  private static func createDataTexture(
    config: RippleAnimationConfig,
    waveOrigin: SIMD3<Float>
  ) -> TextureResource? {
    let width = textureWidth
    let height = textureHeight

    let latSegs = latSegments(for: config.fragmentCount)
    let lonSegs = lonSegments(for: config.fragmentCount)

    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)

    for rowIdx in 0..<height {
      // Cols 0-2: Lookup table data (random physics values)
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

        // Col 4: lonSegments (RG), waveSpeed (BA) - waveSpeed not used by ripple
        let lonSegs16 = UInt16(clamping: lonSegs)
        pixels.append(UInt8((lonSegs16 >> 8) & 0xFF))
        pixels.append(UInt8(lonSegs16 & 0xFF))
        pixels.append(contentsOf: [0, 0])

        // Col 5-6: wave origin
        let ox16 = encode16bit(waveOrigin.x, min: -2.0, max: 2.0)
        let oy16 = encode16bit(waveOrigin.y, min: -2.0, max: 2.0)
        let oz16 = encode16bit(waveOrigin.z, min: -2.0, max: 2.0)
        pixels.append(UInt8((ox16 >> 8) & 0xFF))
        pixels.append(UInt8(ox16 & 0xFF))
        pixels.append(UInt8((oy16 >> 8) & 0xFF))
        pixels.append(UInt8(oy16 & 0xFF))
        pixels.append(UInt8((oz16 >> 8) & 0xFF))
        pixels.append(UInt8(oz16 & 0xFF))
        pixels.append(1)  // wave enabled
        pixels.append(0)

        // Col 7: Algorithm ID (R = 2 for ripple)
        pixels.append(2)  // ALGORITHM_RIPPLE
        pixels.append(contentsOf: [0, 0, 0])

        // Col 8: baseGravity (RG), gravityMin (BA)
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

        // Col 10: spinRateMax (RG), baseSpeed (BA) - baseSpeed not used by ripple
        let spinMax16 = encode16bit(config.spinRateMax, min: 0.0, max: 20.0)
        pixels.append(UInt8((spinMax16 >> 8) & 0xFF))
        pixels.append(UInt8(spinMax16 & 0xFF))
        pixels.append(contentsOf: [128, 128])  // baseSpeed = 0 (neutral)

        // Col 11: spreadAngle (RG), upwardBias (BA) - not used by ripple
        pixels.append(contentsOf: [128, 128, 128, 128])

        // Col 12: waveFrequency (RG), waveAmplitude (BA)
        let waveFreq16 = encode16bit(config.waveFrequency, min: 1.0, max: 10.0)
        let waveAmp16 = encode16bit(config.waveAmplitude, min: 0.0, max: 0.2)
        pixels.append(UInt8((waveFreq16 >> 8) & 0xFF))
        pixels.append(UInt8(waveFreq16 & 0xFF))
        pixels.append(UInt8((waveAmp16 >> 8) & 0xFF))
        pixels.append(UInt8(waveAmp16 & 0xFF))

        // Col 13: collapseSpeed (RG), rippleSpeed (BA)
        let collapse16 = encode16bit(config.collapseSpeed, min: 0.0, max: 2.0)
        let rippleSpd16 = encode16bit(config.rippleSpeed, min: 0.0, max: 2.0)
        pixels.append(UInt8((collapse16 >> 8) & 0xFF))
        pixels.append(UInt8(collapse16 & 0xFF))
        pixels.append(UInt8((rippleSpd16 >> 8) & 0xFF))
        pixels.append(UInt8(rippleSpd16 & 0xFF))

        // Cols 14-31: padding
        for _ in 14..<width {
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
      rippleLog.error("CGDataProvider creation failed")
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
      rippleLog.error("CGImage creation failed")
      return nil
    }

    do {
      return try TextureResource(image: cgImage, withName: "RippleData", options: .init(semantic: .raw))
    } catch {
      rippleLog.error("Failed to create texture: \(error)")
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
