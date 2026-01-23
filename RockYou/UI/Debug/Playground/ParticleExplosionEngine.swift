// ParticleExplosionEngine.swift
// RockYou
//
// ConfigurableEngine for particle explosion/shatter effect.
// Controls fragment count, physics parameters, and wave propagation.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Engine for dome particle explosion (shatter) effect.
///
/// Controls the physics and appearance of fragment particles.
/// The simulation playback is handled by DomeShatterGPU.
@Observable
final class ParticleExplosionEngine: ConfigurableEngine {

  // MARK: - Fragment Configuration

  var fragmentCount: Int = 50000
  var domeRadius: Double = 0.5

  // MARK: - Physics
  // Note: effective gravity = baseGravity * random(gravityMin...gravityMax)
  // gravityMin/Max are multipliers, not direct values

  var baseGravity: Double = 0.2
  var gravityMin: Double = 0.5
  var gravityMax: Double = 1.5
  var spinRateMin: Double = 4.0
  var spinRateMax: Double = 8.0

  // MARK: - Wave Propagation

  var waveEnabled: Bool = true
  var waveSpeed: Double = 2.0

  // MARK: - Display Options

  var showDpadTexture: Bool = true

  // MARK: - Property Descriptors

  // Note: fragmentCount is handled separately with a TextField in the view
  static let propertyDescriptors: [String: PropertyDescriptor] = [
    "domeRadius": .init("Dome Radius", .slider(min: 0.2, max: 1.0, step: 0.05)),
    "baseGravity": .init("Base Gravity", .slider(min: 0.05, max: 1.0, step: 0.05)),
    "gravityMin": .init("Gravity Min (multiplier)", .slider(min: 0.1, max: 2.0, step: 0.1)),
    "gravityMax": .init("Gravity Max (multiplier)", .slider(min: 0.1, max: 2.0, step: 0.1)),
    "spinRateMin": .init("Spin Rate Min", .slider(min: 0, max: 20, step: 0.5)),
    "spinRateMax": .init("Spin Rate Max", .slider(min: 0, max: 20, step: 0.5)),
    "waveEnabled": .init("Wave Propagation", .toggle),
    "waveSpeed": .init("Wave Speed", .slider(min: 0.5, max: 5.0, step: 0.1)),
    "showDpadTexture": .init("DPad Texture", .toggle),
  ]

  // MARK: - Dynamic Accessors

  func getValue(forKey key: String) -> Any? {
    switch key {
    case "fragmentCount": return fragmentCount
    case "domeRadius": return domeRadius
    case "baseGravity": return baseGravity
    case "gravityMin": return gravityMin
    case "gravityMax": return gravityMax
    case "spinRateMin": return spinRateMin
    case "spinRateMax": return spinRateMax
    case "waveEnabled": return waveEnabled
    case "waveSpeed": return waveSpeed
    case "showDpadTexture": return showDpadTexture
    default: return nil
    }
  }

  func setValue(_ value: Any, forKey key: String) {
    switch key {
    case "fragmentCount": if let v = value as? Int { fragmentCount = v }
    case "domeRadius": if let v = value as? Double { domeRadius = v }
    case "baseGravity": if let v = value as? Double { baseGravity = v }
    case "gravityMin": if let v = value as? Double { gravityMin = v }
    case "gravityMax": if let v = value as? Double { gravityMax = v }
    case "spinRateMin": if let v = value as? Double { spinRateMin = v }
    case "spinRateMax": if let v = value as? Double { spinRateMax = v }
    case "waveEnabled": if let v = value as? Bool { waveEnabled = v }
    case "waveSpeed": if let v = value as? Double { waveSpeed = v }
    case "showDpadTexture": if let v = value as? Bool { showDpadTexture = v }
    default: break
    }
  }

  // MARK: - Conversion to DomeShatterConfig

  /// Converts engine parameters to DomeShatterConfig for simulation
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
}
