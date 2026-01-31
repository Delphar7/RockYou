// DomeBladeMeshView.swift
// RockYou/UI/Debug/Playground
//
// Debug-only shatter configuration for playground experimentation.
// DomeBladeMeshConfig and DomeBladeMeshGenerator live in UI/Dome/DomeBladeMesh.swift.

import Foundation

// MARK: - Shatter Configuration

/// Configuration for GPU shatter effect
struct DomeShatterConfig {
  var baseSpeed: Float = 0.000  // Outward velocity (near zero for "in place" feel)
  var upwardBias: Float = 0.003  // Upward velocity component (minimal)
  var spreadAngle: Float = 0.001  // Random spread (radians) - very small
  var gravityMin: Float = 0.3  // Min gravity multiplier
  var gravityMax: Float = 0.5  // Max gravity multiplier
  var baseGravity: Float = 0.2  // Base gravity value (gentler fall)
  var spinRateMin: Float = 6.0  // Min spin (rad/s)
  var spinRateMax: Float = 6.0  // Max spin (rad/s)
  var inheritedSpinScale: Float = 0.1  // How much blade motion transfers to fragments
  var fragmentSampleRate: Float = 1.0  // Fraction of triangles to use (1.0 = all)

  // Tessellated dome fragment count
  var tessellatedFragmentCount: Int = 50000

  static let `default` = DomeShatterConfig()
}
