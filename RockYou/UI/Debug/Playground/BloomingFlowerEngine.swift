// BloomingFlowerEngine.swift
// RockYou
//
// ConfigurableEngine for dome iris blade geometry.
// Controls blade count, coverage, thickness, and display options.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Engine for dome iris "blooming flower" blade animation.
///
/// Controls the geometry of iris blades that open/close like a flower.
/// The aperture animation is handled separately via AnimationScrubber.
@Observable
final class BloomingFlowerEngine: ConfigurableEngine {

  // MARK: - Blade Geometry

  var bladeCount: Int = 10
  var bladeCoverage: Double = 0.85
  var bladeOverlap: Double = 0.02

  // MARK: - Display Options

  var showDpadTexture: Bool = true
  var showMetalLayer: Bool = true

  // MARK: - Property Descriptors

  static let propertyDescriptors: [String: PropertyDescriptor] = [
    "bladeCount": .init("Blade Count", .intStepper(min: 3, max: 24, step: 1)),
    "bladeCoverage": .init("Coverage", .slider(min: 0.3, max: 1.0, step: 0.01)),
    "bladeOverlap": .init("Overlap", .slider(min: 0, max: 0.1, step: 0.005)),
    "showDpadTexture": .init("DPad Texture", .toggle),
    "showMetalLayer": .init("Metal Layer", .toggle),
  ]

  // MARK: - Dynamic Accessors

  func getValue(forKey key: String) -> Any? {
    switch key {
    case "bladeCount": return bladeCount
    case "bladeCoverage": return bladeCoverage
    case "bladeOverlap": return bladeOverlap
    case "showDpadTexture": return showDpadTexture
    case "showMetalLayer": return showMetalLayer
    default: return nil
    }
  }

  func setValue(_ value: Any, forKey key: String) {
    switch key {
    case "bladeCount": if let v = value as? Int { bladeCount = v }
    case "bladeCoverage": if let v = value as? Double { bladeCoverage = v }
    case "bladeOverlap": if let v = value as? Double { bladeOverlap = v }
    case "showDpadTexture": if let v = value as? Bool { showDpadTexture = v }
    case "showMetalLayer": if let v = value as? Bool { showMetalLayer = v }
    default: break
    }
  }

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
