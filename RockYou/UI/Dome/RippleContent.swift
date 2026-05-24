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

  /// SceneContent protocol - animation complete when all fragments gone
  var isComplete: Bool { visibilityTracker.allFragmentsGone }

  private let domeEntity: ModelEntity
  private var dataTexture: TextureResource?
  private var mtlDataTexture: MTLTexture?  // Raw Metal texture for compute shader
  private var lowLevelMesh: LowLevelMesh?  // Retains zero-copy buffers backing the dome mesh
  private let fragmentCount: Int
  private let visibilityTracker = VisibilityTracker()

  init(config: RippleAnimationConfig, cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]) {
    self.config = config

    // Create root entity
    let root = Entity()

    // Compute tessellation segments
    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    // Actual fragment count from tessellation
    self.fragmentCount = DomeMeshGenerator.fragmentCount(latSegments: latSegs, lonSegments: lonSegs)

    // Generate dome mesh
    guard let meshGenerator = DomeMeshGenerator(),
          let generated = meshGenerator.generateMesh(
            latSegments: latSegs,
            lonSegments: lonSegs,
            radius: config.domeRadius
          ) else {
      rippleLog.error("Failed to generate dome mesh")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    self.lowLevelMesh = generated.lowLevelMesh

    // Compute wave origin: 45 degrees around Y from camera-facing point
    let cameraDir = simd_normalize(cameraPosition)
    let angle: Float = .pi / 4
    let rotatedDir = SIMD3<Float>(
      cameraDir.x * cos(angle) - cameraDir.z * sin(angle),
      cameraDir.y,
      cameraDir.x * sin(angle) + cameraDir.z * cos(angle)
    )
    let waveOrigin = rotatedDir * config.domeRadius * 0.8

    // Create data texture for shader params (also creates MTLTexture for compute)
    let textureResult = Self.createDataTexture(config: config, waveOrigin: waveOrigin)
    guard let texture = textureResult.resource else {
      rippleLog.error("Failed to create data texture")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }
    self.dataTexture = texture
    self.mtlDataTexture = textureResult.mtlTexture

    // Create material with ripple shaders
    guard let material = Self.createMaterial(texture: texture) else {
      rippleLog.error("Failed to create ripple material")
      self.entity = root
      self.domeEntity = ModelEntity()
      return
    }

    // Create dome entity
    let dome = ModelEntity(mesh: generated.resource, materials: [material])
    root.addChild(dome)
    self.domeEntity = dome

    // Add DPad backdrop plane if enabled
    if config.showDpadTexture,
       let backdrop = DPadBackdrop.makeEntity(
         radius: config.domeRadius,
         name: "DPad-Ripple-Backdrop"
       ) {
      root.addChild(backdrop)
    }

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
      animation: RippleVisibilityAdapter(texture: mtlTexture, fragmentCount: fragmentCount)
    ) {
      rippleLog.info("All fragments gone at t=\(time)")
    }
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

  private static func createDataTexture(
    config: RippleAnimationConfig,
    waveOrigin: SIMD3<Float>
  ) -> TextureParamWriter.TextureResult {
    let latSegs = DomeMeshGenerator.latSegments(for: config.fragmentCount)
    let lonSegs = DomeMeshGenerator.lonSegments(for: config.fragmentCount)

    var params = TextureParamWriter()

    // Shared dome params
    params.writeFloat16(config.domeRadius, at: TextureParam.radius, min: 0.0, max: 2.0)
    params.writeInt16(latSegs, at: TextureParam.latSegments)
    params.writeInt16(lonSegs, at: TextureParam.lonSegments)

    // Wave origin (always enabled for ripple)
    params.writeFloat16(waveOrigin.x, at: TextureParam.waveOriginX, min: -2.0, max: 2.0)
    params.writeFloat16(waveOrigin.y, at: TextureParam.waveOriginY, min: -2.0, max: 2.0)
    params.writeFloat16(waveOrigin.z, at: TextureParam.waveOriginZ, min: -2.0, max: 2.0)
    params.writeInt16(1, at: TextureParam.waveEnabled)

    // Algorithm ID
    params.writeInt16(2, at: TextureParam.algorithmID)

    // Physics config
    params.writeFloat16(config.baseGravity, at: TextureParam.baseGravity, min: 0.0, max: 2.0)
    params.writeFloat16(config.gravityMin, at: TextureParam.gravityMin, min: 0.0, max: 2.0)
    params.writeFloat16(config.gravityMax, at: TextureParam.gravityMax, min: 0.0, max: 2.0)
    params.writeFloat16(config.spinRateMin, at: TextureParam.spinRateMin, min: 0.0, max: 20.0)
    params.writeFloat16(config.spinRateMax, at: TextureParam.spinRateMax, min: 0.0, max: 20.0)

    // Ripple-specific
    params.writeFloat16(config.waveFrequency, at: TextureParam.waveFrequency, min: 1.0, max: 10.0)
    params.writeFloat16(config.waveAmplitude, at: TextureParam.waveAmplitude, min: 0.0, max: 0.2)
    params.writeFloat16(config.rippleSpeed, at: TextureParam.rippleSpeed, min: 0.0, max: 2.0)

    return params.createTexture(name: "RippleData")
  }

}

// MARK: - Visibility Adapter

/// Adapter to make RippleContent work with VisibilityChecker
private struct RippleVisibilityAdapter: VisibilityCheckable {
  let texture: MTLTexture
  let fragmentCount: Int

  var visibilityKernelName: String { "rippleVisibilityKernel" }

  func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder) {
    // Buffer 2: fragment count (buffer 0 = anyVisible, buffer 1 = time)
    var count = UInt32(fragmentCount)
    encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

    // Texture 0: data texture
    encoder.setTexture(texture, index: 0)
  }
}
