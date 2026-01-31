// BloomingFlowerEngine.swift
// RockYou/UI/Debug/Playground
//
// Playground engine for blooming flower blade animation.
// Uses FlowerContent for rendering via SceneView.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Playground engine for blooming flower blade animation.
/// Uses FlowerContent for rendering via SceneView.
@Observable
final class BloomingFlowerEngine: ContentEngine {
  typealias Content = FlowerContent

  // MARK: - Config

  var config = FlowerAnimationConfig()

  // MARK: - ContentEngine

  static let timeRange: ClosedRange<Double> = 0...8.0

  func makeContent() -> FlowerContent {
    FlowerContent(config: config)
  }

  // MARK: - PropertyConfig (UI Bindings)

  static let propertyConfig: [PropertyConfig<BloomingFlowerEngine>] = [
    .stepper(\.config.bladeCount, "Blade Count", 3...24, step: 1),
    .slider(\.config.bladeCoverage, "Coverage", 0.3...1.0, step: 0.01),
    .slider(\.config.bladeOverlap, "Overlap", 0...0.1, step: 0.005),
    .slider(\.config.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),
    .slider(\.config.openDuration, "Duration", 1.0...10.0, step: 0.5),
  ]
}
