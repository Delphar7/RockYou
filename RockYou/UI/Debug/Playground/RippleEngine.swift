// RippleEngine.swift
// RockYou
//
// Engine for ripple dome shatter effect.
// Radial sin wave from impact point, random detach, then collapse wave.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

/// Engine for ripple dome shatter effect.
@Observable
final class RippleEngine: PlaygroundEngine {

  // MARK: - Properties

  var fragmentCount: Int = 50000
  var domeRadius: Double = 0.5
  var baseGravity: Double = 0.2
  var gravityMin: Double = 0.5
  var gravityMax: Double = 1.5
  var spinRateMin: Double = 4.0
  var spinRateMax: Double = 8.0
  var rippleFrequency: Double = 8.0   // How many waves visible at once
  var rippleAmplitude: Double = 0.006 // Wave height (subtle ripple)
  var rippleSpeed: Double = 0.1       // How fast waves expand outward (gentle)
  var collapseSpeed: Double = 0.3
  var showDpadTexture: Bool = true

  // MARK: - Config

  static let config: [PropertyConfig<RippleEngine>] = [
    .intField(\.fragmentCount, "Fragment Count"),
    .slider(\.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),
    .slider(\.rippleAmplitude, "Wave Height", 0.002...0.02, step: 0.001),
    .slider(\.rippleFrequency, "Wave Count", 4.0...16.0, step: 1.0),
    .slider(\.rippleSpeed, "Wave Speed", 0.02...0.3, step: 0.02),
    .slider(\.baseGravity, "Gravity", 0.05...2.0, step: 0.05),
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

  static let timeRange: ClosedRange<Double> = 0...30.0

  func startSimulation(
    gpuShatterSim: DomeShatterGPU,
    in anchor: AnchorEntity,
    cameraPosition: SIMD3<Float>
  ) {
    // Ripple starts 45 degrees around Y from camera-facing point
    let cameraDir = simd_normalize(cameraPosition)
    let angle: Float = .pi / 4
    let rotatedDir = SIMD3<Float>(
      cameraDir.x * cos(angle) - cameraDir.z * sin(angle),
      cameraDir.y,
      cameraDir.x * sin(angle) + cameraDir.z * cos(angle)
    )
    let waveOrigin = rotatedDir * Float(domeRadius) * 0.8

    gpuShatterSim.start(
      fragmentCount: fragmentCount,
      radius: Float(domeRadius),
      in: anchor,
      config: toShatterConfig(),
      algorithm: .ripple,
      waveOrigin: waveOrigin,
      waveSpeed: 0,  // Ripple uses rippleSpeed instead
      rippleFrequency: Float(rippleFrequency),
      rippleAmplitude: Float(rippleAmplitude),
      rippleSpeed: Float(rippleSpeed),
      collapseSpeed: Float(collapseSpeed),
      cameraPosition: cameraPosition
    )
  }
}
