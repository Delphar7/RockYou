// BloomingFlowerEngine.swift
// RockYou
//
// Engine for dome iris blade geometry.
// Controls blade count, coverage, thickness, and display options.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Engine for dome iris "blooming flower" blade animation.
///
/// Controls the geometry of iris blades that open/close like a flower.
/// The aperture animation is handled separately via AnimationScrubber.
@Observable
final class BloomingFlowerEngine {

  // MARK: - Properties

  var bladeCount: Int = 10
  var bladeCoverage: Double = 0.85
  var bladeOverlap: Double = 0.02
  var showDpadTexture: Bool = true
  var showMetalLayer: Bool = true

  // MARK: - Config

  static let config: [PropertyConfig<BloomingFlowerEngine>] = [
    .stepper(\.bladeCount, "Blade Count", 3...24, step: 1),
    .slider(\.bladeCoverage, "Coverage", 0.3...1.0, step: 0.01),
    .slider(\.bladeOverlap, "Overlap", 0...0.1, step: 0.005),
    .toggle(\.showDpadTexture, "DPad Texture"),
    .toggle(\.showMetalLayer, "Metal Layer"),
  ]

  // MARK: - Conversion to DomeBladeMeshConfig

  /// Converts engine parameters to DomeBladeMeshConfig for mesh generation
  func toMeshConfig(domeRadius: Float = 0.5) -> DomeBladeMeshConfig {
    var config = DomeBladeMeshConfig()
    config.bladeCount = bladeCount
    config.domeRadius = domeRadius
    config.bladeCoverage = Float(bladeCoverage)
    config.bladeOverlap = Float(bladeOverlap)
    return config
  }
}
