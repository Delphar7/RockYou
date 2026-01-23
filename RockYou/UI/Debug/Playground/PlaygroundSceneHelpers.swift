// PlaygroundSceneHelpers.swift
// RockYou
//
// Shared utilities for playground RealityKit scenes.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

// MARK: - Camera Helpers

enum PlaygroundCamera {
  /// Computes camera position on a sphere looking at origin.
  static func position(yaw: Float, pitch: Float, distance: Float) -> SIMD3<Float> {
    let yawRad = yaw * .pi / 180
    let pitchRad = pitch * .pi / 180
    let x = distance * cos(pitchRad) * sin(yawRad)
    let y = distance * sin(pitchRad)
    let z = distance * cos(pitchRad) * cos(yawRad)
    return SIMD3<Float>(x, y, z)
  }
}

// MARK: - Scene Setup

enum PlaygroundScene {
  /// Creates standard lighting setup for playground scenes.
  static func makeLighting() -> AnchorEntity {
    let lightAnchor = AnchorEntity(world: .zero)

    let key = DirectionalLight()
    key.light.intensity = 2000
    key.look(at: .zero, from: SIMD3<Float>(0.8, 1.2, 0.6), relativeTo: nil)
    lightAnchor.addChild(key)

    let fill = PointLight()
    fill.light.intensity = 400
    fill.position = SIMD3<Float>(-0.5, 0.3, 0.8)
    lightAnchor.addChild(fill)

    return lightAnchor
  }

  /// Creates DPad backdrop entity.
  @MainActor
  static func makeBackdropEntity() -> ModelEntity? {
    guard let path = Bundle.main.path(forResource: "DPad-Refracted", ofType: "png"),
      let native = PlatformImage.cachedNativeContentsOfFile(path),
      let cg = PlatformImage.cgImage(from: native)
    else {
      return nil
    }

    let tex: TextureResource
    do {
      tex = try TextureResource(
        image: cg, withName: "DPad-Backdrop", options: .init(semantic: .color))
    } catch {
      return nil
    }

    let mesh = MeshResource.generatePlane(width: 1, depth: 1)
    var mat = UnlitMaterial()
    mat.color = .init(texture: .init(tex))
    mat.blending = .transparent(opacity: 1.0)

    return ModelEntity(mesh: mesh, materials: [mat])
  }
}

// MARK: - Camera Controls View

/// Reusable camera orbit controls for playground views.
struct PlaygroundCameraControls: View {
  @Binding var yawDegrees: Double
  @Binding var pitchDegrees: Double
  @Binding var distance: Double

  var yawRange: ClosedRange<Double> = -180...180
  var pitchRange: ClosedRange<Double> = -89...89
  var distanceRange: ClosedRange<Double> = 0.5...3.0

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledContent("Yaw") {
        HStack {
          Slider(value: $yawDegrees, in: yawRange)
          Text(String(format: "%.0f°", yawDegrees))
            .font(.system(.caption, design: .monospaced))
            .frame(width: 45)
        }
      }

      LabeledContent("Pitch") {
        HStack {
          Slider(value: $pitchDegrees, in: pitchRange)
          Text(String(format: "%.0f°", pitchDegrees))
            .font(.system(.caption, design: .monospaced))
            .frame(width: 45)
        }
      }

      LabeledContent("Distance") {
        HStack {
          Slider(value: $distance, in: distanceRange)
          Text(String(format: "%.2f", distance))
            .font(.system(.caption, design: .monospaced))
            .frame(width: 45)
        }
      }
    }
  }
}
