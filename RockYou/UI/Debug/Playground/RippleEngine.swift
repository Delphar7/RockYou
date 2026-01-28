// RippleEngine.swift
// RockYou/UI/Debug/Playground
//
// Playground engine for ripple dome animation.
// Implements ContentEngine for RealityDebugView.

import RealityKit
import SwiftUI

/// Playground engine for ripple dome effect.
@Observable
final class RippleEngine: ContentEngine {
  typealias Content = RippleContent

  // MARK: - Config

  var config = RippleAnimationConfig()

  // Store camera position for wave origin calculation
  var cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]

  // MARK: - ContentEngine

  static let timeRange: ClosedRange<Double> = 0...30.0

  func makeContent() -> RippleContent {
    RippleContent(config: config, cameraPosition: cameraPosition)
  }

  // MARK: - PropertyConfig (UI Bindings)

  static let propertyConfig: [PropertyConfig<RippleEngine>] = [
    .intField(\.config.fragmentCount, "Fragment Count"),
    .slider(\.config.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),
    .slider(\.config.waveAmplitude, "Wave Height", 0.002...0.1, step: 0.002),
    .slider(\.config.waveFrequency, "Wave Count", 2.0...16.0, step: 1.0),
    .slider(\.config.rippleSpeed, "Wave Speed", 0.02...0.5, step: 0.02),
    .slider(\.config.baseGravity, "Gravity", 0.05...1.0, step: 0.05),
    .toggle(\.config.showDpadTexture, "DPad Texture"),
  ]
}
