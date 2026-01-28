// DoorsView.swift
// RockYou/UI/Dome
//
// 3D "emergency dome doors" over the DPad.
// Uses SceneView with IrisContent for GPU-driven iris mechanism animation.

import Foundation
import RealityKit
import SwiftUI

struct DomeDoorsView: View {
  /// 0 = closed dome, 1 = fully opened (doors moved away)
  var openProgress: CGFloat

  /// Optional debug override for the camera orbit.
  var debugCameraOrbit: DomeDebugCameraOrbit? = nil

  // Animation config (can be randomized for variety)
  private let irisConfig: IrisAnimationConfig

  @State private var content: IrisContent?

  init(openProgress: CGFloat, debugCameraOrbit: DomeDebugCameraOrbit? = nil) {
    self.openProgress = openProgress
    self.debugCameraOrbit = debugCameraOrbit

    // Create config for production use
    var config = IrisAnimationConfig.randomized()
    config.domeRadius = DomeSceneConfig.domeRadius
    config.openDuration = DomeSceneConfig.openDuration
    config.showSeamRibbons = true
    self.irisConfig = config
  }

  var body: some View {
    GeometryReader { _ in
      if let content {
        SceneView(
          content: content,
          time: Float(openProgress) * irisConfig.openDuration,
          cameraPosition: cameraPosition(for: Float(openProgress)),
          cameraFOV: DomeSceneConfig.cameraFovDegrees
        )
        .onAppear {
          // Position and scale are applied to the content entity
          content.entity.position = [0, 0.01, 0]
          let s = DomeSceneConfig.domeEntityScale
          content.entity.scale = [s, s, s]
        }
      }
    }
    .allowsHitTesting(false)
    .onAppear {
      // Create content lazily on appear
      if content == nil {
        content = IrisContent(config: irisConfig)
      }
    }
  }

  /// Computes camera position, using debug override if available
  private func cameraPosition(for progress: Float) -> SIMD3<Float> {
    if let orbit = debugCameraOrbit {
      let yawRadians = orbit.yawDegrees * .pi / 180
      let pitchRadians = orbit.pitchDegrees * .pi / 180
      let distance = max(0.1, orbit.distance)
      let x = sin(yawRadians) * cos(pitchRadians) * distance
      let z = cos(yawRadians) * cos(pitchRadians) * distance
      let y = sin(pitchRadians) * distance
      return [x, y, z]
    }
    return cameraPositionForProgress(progress)
  }
}

struct DomeDebugCameraOrbit {
  var yawDegrees: Float
  var pitchDegrees: Float
  var distance: Float
}

/// Computes camera position for a given progress (0=closed, 1=open).
/// Orbits from startYaw by orbitDegrees while lifting from startPitch to endPitch.
private func cameraPositionForProgress(_ progress: Float) -> SIMD3<Float> {
  let t = min(1, max(0, progress))

  // Yaw: linear, but reversed direction (subtract instead of add)
  let yawDegrees = DomeSceneConfig.cameraStartYawDegrees - DomeSceneConfig.cameraOrbitDegrees * t

  // Pitch: ease-in (t²) so lift accelerates toward the end
  let tEased = t * t
  let pitchDegrees = DomeSceneConfig.cameraStartPitchDegrees +
    (DomeSceneConfig.cameraEndPitchDegrees - DomeSceneConfig.cameraStartPitchDegrees) * tEased

  let yawRadians = yawDegrees * .pi / 180
  let pitchRadians = pitchDegrees * .pi / 180
  let distance = DomeSceneConfig.cameraDistance

  let x = sin(yawRadians) * cos(pitchRadians) * distance
  let z = cos(yawRadians) * cos(pitchRadians) * distance
  let y = sin(pitchRadians) * distance

  return [x, y, z]
}
