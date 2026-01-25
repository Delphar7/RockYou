// ConfettiEngine.swift
// RockYou
//
// Engine for confetti dome shatter effect.
// Fragments flutter down like confetti with optional cannon launch.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

/// Engine for confetti dome shatter effect.
@Observable
final class ConfettiEngine: PlaygroundEngine {

  // MARK: - Properties

  var fragmentCount: Int = 50000
  var domeRadius: Double = 0.5
  var baseGravity: Double = 0.2
  var gravityMin: Double = 0.5
  var gravityMax: Double = 1.5
  var spinRateMin: Double = 4.0
  var spinRateMax: Double = 8.0
  var waveEnabled: Bool = true
  var waveSpeed: Double = 2.0
  var cannonPower: Double = 0.0
  var showDpadTexture: Bool = true

  // MARK: - Config

  static let config: [PropertyConfig<ConfettiEngine>] = [
    .intField(\.fragmentCount, "Fragment Count"),
    .slider(\.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),
    .slider(\.baseGravity, "Base Gravity", 0.05...1.0, step: 0.05),
    .slider(\.gravityMin, "Gravity Min", 0.1...2.0, step: 0.1),
    .slider(\.gravityMax, "Gravity Max", 0.1...2.0, step: 0.1),
    .slider(\.spinRateMin, "Spin Rate Min", 0...20, step: 0.5),
    .slider(\.spinRateMax, "Spin Rate Max", 0...20, step: 0.5),
    .toggle(\.waveEnabled, "Wave Propagation"),
    .slider(\.waveSpeed, "Wave Speed", 0.5...5.0, step: 0.1),
    .slider(\.cannonPower, "Cannon Power", 0.0...2.0, step: 0.1),
    .toggle(\.showDpadTexture, "DPad Texture"),
  ]

  // MARK: - Conversion to DomeShatterConfig

  func toShatterConfig() -> DomeShatterConfig {
    var config = DomeShatterConfig()
    config.tessellatedFragmentCount = fragmentCount
    config.baseGravity = Float(baseGravity)
    config.gravityMin = Float(gravityMin)
    config.gravityMax = Float(gravityMax)
    config.spinRateMin = Float(spinRateMin)
    config.spinRateMax = Float(spinRateMax)
    return config
  }

  // MARK: - PlaygroundEngine

  static let timeRange: ClosedRange<Double> = 0...10.0

  func startSimulation(
    gpuShatterSim: DomeShatterGPU,
    in anchor: AnchorEntity,
    cameraPosition: SIMD3<Float>
  ) {
    var waveOrigin: SIMD3<Float>? = nil
    if waveEnabled {
      waveOrigin = simd_normalize(cameraPosition) * Float(domeRadius) * 0.8
    }

    gpuShatterSim.start(
      fragmentCount: fragmentCount,
      radius: Float(domeRadius),
      in: anchor,
      config: toShatterConfig(),
      algorithm: .confetti,
      waveOrigin: waveOrigin,
      waveSpeed: Float(waveSpeed),
      cannonPower: Float(cannonPower),
      cameraPosition: cameraPosition
    )
  }
}
