// DoorsView.swift
// RockYou/UI/Dome
//
// 3D "emergency dome doors" over the DPad.
// Uses SceneView with a randomly selected dome animation (iris / ripple / shatter).

import Foundation
import os
import RealityKit
import SwiftUI

private let doorsLog = Logger(subsystem: "com.rockyou", category: "DoorsView")

struct DomeDoorsView: View {
  /// 0 = closed dome, 1 = fully opened (doors moved away)
  var openProgress: CGFloat

  /// Optional debug override for the camera orbit.
  var debugCameraOrbit: DomeDebugCameraOrbit? = nil

  /// Full-screen viewport size (nil = legacy DPad-bound mode).
  var viewportSize: CGSize? = nil

  /// Old dome frame size for scale ratio (nil = legacy mode).
  var referenceDomeSize: CGFloat? = nil

  /// Called when the animation's content reports completion.
  var onComplete: (() -> Void)? = nil

  // Randomly selected animation with production overrides
  private let animation: DomeAnimation

  @State private var content: SceneContent?

  init(
    openProgress: CGFloat,
    debugCameraOrbit: DomeDebugCameraOrbit? = nil,
    viewportSize: CGSize? = nil,
    referenceDomeSize: CGFloat? = nil,
    onComplete: (() -> Void)? = nil
  ) {
    self.openProgress = openProgress
    self.debugCameraOrbit = debugCameraOrbit
    self.viewportSize = viewportSize
    self.referenceDomeSize = referenceDomeSize
    self.onComplete = onComplete

    // iOS Simulator can't render RealityKit content (Apple2 GPU, no CustomMaterial support).
    // Dome animations are device/Mac only; simulator shows nothing — test on-device.
    let selected = DomeAnimationFactory.random()
    self.animation = selected.animation.withProductionDefaults()
    doorsLog.debug("Dome animation: \(selected.name)")
  }

  var body: some View {
    GeometryReader { _ in
      if let content {
        SceneView(
          content: content,
          time: Float(openProgress) * DomeSceneConfig.openDuration,
          cameraPosition: cameraPosition(for: Float(openProgress)),
          cameraFOV: DomeSceneConfig.cameraFovDegrees
        )
        .onAppear {
          // Position and scale are applied to the content entity
          content.entity.position = [0, 0.01, 0]
          let s = computeEntityScale()
          content.entity.scale = [s, s, s]
          Log.debug("DoorsView", "SceneView appeared: scale=\(s) viewportH=\(viewportSize?.height ?? -1) refDome=\(referenceDomeSize ?? -1)")
        }
      }
    }
    .allowsHitTesting(false)
    .onAppear {
      // Create content lazily on appear
      if content == nil {
        let cameraPos = cameraPosition(for: 0)
        Log.debug("DoorsView", "Creating content: viewportSize=\(String(describing: viewportSize)) refDome=\(String(describing: referenceDomeSize))")
        content = animation.makeContent(cameraPosition: cameraPos)
        Log.debug("DoorsView", "Content created: entity.children=\(content?.entity.children.count ?? -1)")
      }
    }
    .onChange(of: openProgress) { _, _ in
      if content?.isComplete == true {
        onComplete?()
      }
    }
  }

  /// Computes entity scale, compensating for a larger viewport so the dome
  /// keeps the same apparent pixel size at center.
  private func computeEntityScale() -> Float {
    let base = DomeSceneConfig.domeEntityScale
    guard let viewportSize, let ref = referenceDomeSize, ref > 0 else { return base }
    return base * Float(ref) / Float(viewportSize.height)
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
