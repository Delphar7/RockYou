// DomeAnimationFactory.swift
// RockYou/UI/Dome
//
// Declarative preset registry for dome animations.
// Randomly selects an effect (iris / ripple / shatter) with randomized parameters
// when the breaker fires.

import Foundation

// MARK: - Preset Definition

/// A named, weighted animation preset.
/// The closure generates a fresh DomeAnimation with randomized parameters on each call.
struct DomeAnimationPreset {
  let name: String
  let weight: Double
  let make: () -> DomeAnimation

  init(name: String, weight: Double = 1.0, make: @escaping () -> DomeAnimation) {
    self.name = name
    self.weight = weight
    self.make = make
  }
}

// MARK: - Factory

/// Registry of animation presets and weighted random selection.
/// Adding a new preset = one line in the `presets` array.
enum DomeAnimationFactory {
  static let presets: [DomeAnimationPreset] = [
    .init(name: "Spiral Iris") { .iris(.randomized()) },
    .init(name: "Ripple") { .ripple(.randomized()) },
    .init(name: "Shatter") { .shatter(.randomized()) },
    .init(name: "Flower") { .flower(.randomized()) },
  ]

  /// Pick a random preset (weighted), invoke its closure to get a fresh animation.
  static func random() -> (name: String, animation: DomeAnimation) {
    let totalWeight = presets.reduce(0.0) { $0 + $1.weight }
    let roll = Double.random(in: 0..<totalWeight)
    var cumulative = 0.0
    for preset in presets {
      cumulative += preset.weight
      if roll < cumulative {
        return (preset.name, preset.make())
      }
    }
    // Fallback (shouldn't happen)
    let last = presets.last!
    return (last.name, last.make())
  }
}

// MARK: - DomeAnimation Content Factory

extension DomeAnimation {
  /// Creates the appropriate SceneContent for this animation.
  @MainActor
  func makeContent(cameraPosition: SIMD3<Float> = [0.6, 0.4, 0.6]) -> SceneContent {
    switch self {
    case .iris(let config):
      return IrisContent(config: config)
    case .shatter(let config):
      return ShatterContent(config: config, cameraPosition: cameraPosition)
    case .ripple(let config):
      return RippleContent(config: config, cameraPosition: cameraPosition)
    case .flower(let config):
      return FlowerContent(config: config)
    }
  }

  /// Returns a copy with production overrides applied (radius, duration, fragmentCount, no debug texture).
  func withProductionDefaults() -> DomeAnimation {
    switch self {
    case .iris(var config):
      config.domeRadius = DomeSceneConfig.domeRadius
      config.openDuration = DomeSceneConfig.openDuration
      config.fragmentCount = 30000
      config.showSeamRibbons = true
      return .iris(config)
    case .shatter(var config):
      config.domeRadius = DomeSceneConfig.domeRadius
      config.fragmentCount = 50000
      config.showDpadTexture = false
      return .shatter(config)
    case .ripple(var config):
      config.domeRadius = DomeSceneConfig.domeRadius
      config.fragmentCount = 50000
      config.showDpadTexture = false
      return .ripple(config)
    case .flower(var config):
      config.domeRadius = DomeSceneConfig.domeRadius
      config.openDuration = DomeSceneConfig.openDuration
      return .flower(config)
    }
  }

  /// The open duration for this animation, used for time scaling.
  var openDuration: Float {
    switch self {
    case .iris(let config):
      return config.openDuration
    case .shatter, .ripple:
      return DomeSceneConfig.openDuration
    case .flower(let config):
      return config.openDuration
    }
  }
}
