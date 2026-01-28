// ShatterEngine.swift
// RockYou/UI/Debug/Playground
//
// Unified engine for explode/confetti dome shatter effects.
// Mode selection switches between physics behaviors.
// Implements ContentEngine for RealityDebugView.

import RealityKit
import SwiftUI

/// Unified playground engine for shatter effects (explode/confetti).
@Observable
final class ShatterEngine: ContentEngine {
  typealias Content = ShatterContent

  // MARK: - Config

  var config = ShatterAnimationConfig()

  // Store camera position for wave origin calculation
  var cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]

  // MARK: - ContentEngine

  static let timeRange: ClosedRange<Double> = 0...10.0

  func makeContent() -> ShatterContent {
    ShatterContent(config: config, cameraPosition: cameraPosition)
  }

  // MARK: - PropertyConfig (UI Bindings)

  static let propertyConfig: [PropertyConfig<ShatterEngine>] = [
    .picker(\.config.mode, "Mode"),
    .intField(\.config.fragmentCount, "Fragment Count"),
    .slider(\.config.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),

    // Shared physics
    .slider(\.config.baseGravity, "Base Gravity", 0.05...1.0, step: 0.05),
    .slider(\.config.gravityMin, "Gravity Min", 0.1...2.0, step: 0.1),
    .slider(\.config.gravityMax, "Gravity Max", 0.1...2.0, step: 0.1),
    .slider(\.config.spinRateMin, "Spin Rate Min", 0.0...20.0, step: 0.5),
    .slider(\.config.spinRateMax, "Spin Rate Max", 0.0...20.0, step: 0.5),

    // Wave
    .toggle(\.config.waveEnabled, "Wave Propagation"),
    .slider(\.config.waveSpeed, "Wave Speed", 0.5...5.0, step: 0.1),

    // Explode-specific
    .slider(\.config.baseSpeed, "Outward Speed", -2.0...2.0, step: 0.05),
    .slider(\.config.spreadAngle, "Spread Angle", 0.0...2.0, step: 0.05),
    .slider(\.config.upwardBias, "Upward Bias", -2.0...2.0, step: 0.05),

    // Confetti-specific
    .slider(\.config.cannonPower, "Cannon Power", 0.0...2.0, step: 0.1),

    // Debug
    .toggle(\.config.showDpadTexture, "DPad Texture"),
  ]
}
