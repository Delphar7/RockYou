// DomeBladeMeshView.swift
// RockYou
//
// 3D blade meshes for the dome iris, supporting aperture animation.

import RealityKit
import SwiftUI
import simd

// MARK: - Configuration

struct DomeBladeMeshConfig: Equatable {
  var bladeCount: Int = 10
  var domeRadius: Float = 0.5

  /// How far blades extend from rim toward pole (0 = rim only, 1 = to pole).
  var bladeCoverage: Float = 0.85

  /// Blade thickness as fraction of dome radius.
  var bladeThickness: Float = 0.015

  /// Angular overlap between adjacent blades (radians). Slight overlap prevents gaps.
  var bladeOverlap: Float = 0.02

  /// Pivot location along blade (0 = outer rim, 1 = inner tip).
  var pivotPosition: Float = 0.1

  /// Segments along blade length (more = smoother curve).
  var lengthSegments: Int = 30

  /// Segments across blade width (more = smoother edges).
  var widthSegments: Int = 12

  static let `default` = DomeBladeMeshConfig()
}

// MARK: - Blade Mesh Generator

enum DomeBladeMeshGenerator {

  /// Material indices for blade mesh parts
  enum MaterialIndex: Int {
    case outer = 0  // Glass (outside of dome)
    case inner = 1  // Metal (inside of dome)
    case edge = 2  // Edge caps
  }

  /// Generates a single-surface blade mesh (no thickness).
  /// This mesh is rendered twice with different face culling to achieve glass/metal sides.
  static func makeBladeSurfaceMesh(
    bladeIndex: Int,
    config: DomeBladeMeshConfig
  ) throws -> MeshResource {
    let N = max(3, config.bladeCount)
    let sectorAngle = (2 * Float.pi) / Float(N)
    let bladeHalfAngle = (sectorAngle / 2) + config.bladeOverlap
    let baseAngle = Float(bladeIndex) * sectorAngle

    let thetaStart = Float.pi / 2  // rim
    let thetaEnd = (Float.pi / 2) * (1 - config.bladeCoverage)  // toward pole

    let lengthSegs = max(2, config.lengthSegments)
    let widthSegs = max(1, config.widthSegments)
    let radius = config.domeRadius

    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    // Helper to compute dome position
    func domePoint(theta: Float, phi: Float) -> SIMD3<Float> {
      let x = radius * sin(theta) * cos(phi)
      let z = radius * sin(theta) * sin(phi)
      let y = radius * cos(theta)
      return SIMD3<Float>(x, y, z)
    }

    // Helper to compute outward normal
    func domeNormal(theta: Float, phi: Float) -> SIMD3<Float> {
      let x = sin(theta) * cos(phi)
      let z = sin(theta) * sin(phi)
      let y = cos(theta)
      return simd_normalize(SIMD3<Float>(x, y, z))
    }

    let cols = widthSegs + 1

    // Single surface following dome curvature
    for i in 0...lengthSegs {
      let t = Float(i) / Float(lengthSegs)
      let theta = thetaStart + t * (thetaEnd - thetaStart)

      for j in 0...widthSegs {
        let s = Float(j) / Float(widthSegs)
        let phi = baseAngle + (s - 0.5) * 2 * bladeHalfAngle

        positions.append(domePoint(theta: theta, phi: phi))
        normals.append(domeNormal(theta: theta, phi: phi))
      }
    }

    // Triangles (CCW winding, outward-facing)
    for i in 0..<lengthSegs {
      for j in 0..<widthSegs {
        let a = UInt32(i * cols + j)
        let b = UInt32((i + 1) * cols + j)
        let c = UInt32((i + 1) * cols + (j + 1))
        let d = UInt32(i * cols + (j + 1))
        indices.append(contentsOf: [a, b, d, b, c, d])
      }
    }

    var desc = MeshDescriptor(name: "blade_surface_\(bladeIndex)")
    desc.positions = MeshBuffers.Positions(positions)
    desc.normals = MeshBuffers.Normals(normals)
    desc.primitives = .triangles(indices)

    return try MeshResource.generate(from: [desc])
  }

  /// Creates glass material for blade exterior (front faces only).
  static func makeGlassMaterial() -> PhysicallyBasedMaterial {
    var glass = PhysicallyBasedMaterial()
    glass.baseColor = .init(tint: .init(red: 0.5, green: 0.6, blue: 0.75, alpha: 0.4))
    glass.roughness = .init(floatLiteral: 0.05)
    glass.metallic = .init(floatLiteral: 0.0)
    glass.blending = .transparent(opacity: .init(floatLiteral: 0.4))
    glass.faceCulling = .back  // Only front faces
    return glass
  }

  /// Creates metal material for blade interior (back faces only).
  static func makeMetalMaterial() -> PhysicallyBasedMaterial {
    var metal = PhysicallyBasedMaterial()
    metal.baseColor = .init(tint: .init(red: 0.8, green: 0.82, blue: 0.85, alpha: 1.0))
    metal.roughness = .init(floatLiteral: 0.15)
    metal.metallic = .init(floatLiteral: 0.95)
    metal.faceCulling = .front  // Only back faces
    return metal
  }
}

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
