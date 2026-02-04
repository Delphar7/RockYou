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

  /// SceneContent protocol - animation complete when all fragments gone
  var isComplete: Bool { visibilityTracker.allFragmentsGone }

  private let domeEntity: ModelEntity
  private var dataTexture: TextureResource?
  private var mtlDataTexture: MTLTexture?  // Raw Metal texture for compute shader
  private let fragmentCount: Int
  private let visibilityTracker = VisibilityTracker()

  init(config: ShatterAnimationConfig, cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]) {
    self.config = config

    // Create root entity
    let root = Entity()

    // Generate dome mesh
    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    guard let meshGenerator = DomeMeshGenerator(),
          let mesh = meshGenerator.generateMesh(
            latSegments: latSegs,
            lonSegments: lonSegs,
            radius: config.domeRadius
          ) else {
      shatterLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      self.fragmentCount = 0
      return
    }

    self.fragmentCount = DomeMeshGenerator.fragmentCount(latSegments: latSegs, lonSegments: lonSegs)

    // Compute wave origin from camera position if wave enabled
    let waveOrigin: SIMD3<Float>? = config.waveEnabled
      ? simd_normalize(cameraPosition) * config.domeRadius * 0.8
      : nil

    // Create data texture for shader params (also creates MTLTexture for compute)
    let textureResult = Self.createDataTexture(config: config, waveOrigin: waveOrigin)
    guard let texture = textureResult.resource else {
      shatterLog.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    self.dataTexture = texture
    self.mtlDataTexture = textureResult.mtlTexture

    // Create material with appropriate shaders
    guard let material = Self.createMaterial(config: config, texture: texture) else {
      shatterLog.error("Failed to create shatter material")
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

    checkVisibility(at: time)
  }

  // MARK: - Visibility Checking

  private func checkVisibility(at time: Float) {
    guard let mtlTexture = mtlDataTexture else { return }
    visibilityTracker.checkIfNeeded(
      at: time,
      animation: ShatterVisibilityAdapter(texture: mtlTexture, fragmentCount: fragmentCount, mode: config.mode)
    ) {
      shatterLog.info("All fragments gone at t=\(time)")
    }
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

  private static func createDataTexture(
    config: ShatterAnimationConfig,
    waveOrigin: SIMD3<Float>?
  ) -> TextureParamWriter.TextureResult {
    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    var params = TextureParamWriter()

    // Shared dome params
    params.writeFloat16(config.domeRadius, at: TextureParam.radius, min: 0.0, max: 2.0)
    params.writeInt16(latSegs, at: TextureParam.latSegments)
    params.writeInt16(lonSegs, at: TextureParam.lonSegments)
    params.writeFloat16(config.waveSpeed, at: TextureParam.waveSpeed, min: 0.0, max: 20.0)

    // Wave origin
    if let origin = waveOrigin {
      params.writeFloat16(origin.x, at: TextureParam.waveOriginX, min: -2.0, max: 2.0)
      params.writeFloat16(origin.y, at: TextureParam.waveOriginY, min: -2.0, max: 2.0)
      params.writeFloat16(origin.z, at: TextureParam.waveOriginZ, min: -2.0, max: 2.0)
      params.writeInt16(1, at: TextureParam.waveEnabled)
    }

    // Algorithm ID + cannon power
    let algorithmID = config.mode == .explode ? 0 : 1
    params.writeInt16(algorithmID, at: TextureParam.algorithmID)
    params.writeFloat16(config.cannonPower, at: TextureParam.cannonPower, min: 0.0, max: 5.0)

    // Physics config
    params.writeFloat16(config.baseGravity, at: TextureParam.baseGravity, min: 0.0, max: 2.0)
    params.writeFloat16(config.gravityMin, at: TextureParam.gravityMin, min: 0.0, max: 2.0)
    params.writeFloat16(config.gravityMax, at: TextureParam.gravityMax, min: 0.0, max: 2.0)
    params.writeFloat16(config.spinRateMin, at: TextureParam.spinRateMin, min: 0.0, max: 20.0)
    params.writeFloat16(config.spinRateMax, at: TextureParam.spinRateMax, min: 0.0, max: 20.0)
    params.writeFloat16(config.baseSpeed, at: TextureParam.baseSpeed, min: -2.0, max: 2.0)
    params.writeFloat16(config.spreadAngle, at: TextureParam.spreadAngle, min: 0.0, max: 2.0)
    params.writeFloat16(config.upwardBias, at: TextureParam.upwardBias, min: -2.0, max: 2.0)

    return params.createTexture(name: "ShatterData")
  }
}

// MARK: - Visibility Adapter

/// Adapter to make ShatterContent work with VisibilityChecker
private struct ShatterVisibilityAdapter: VisibilityCheckable {
  let texture: MTLTexture
  let fragmentCount: Int
  let mode: ShatterMode

  var visibilityKernelName: String {
    switch mode {
    case .explode: return "explodeVisibilityKernel"
    case .confetti: return "confettiVisibilityKernel"
    }
  }

  func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder) {
    // Buffer 2: fragment count (buffer 0 = anyVisible, buffer 1 = time)
    var count = UInt32(fragmentCount)
    encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

    // Texture 0: data texture
    encoder.setTexture(texture, index: 0)
  }
}
