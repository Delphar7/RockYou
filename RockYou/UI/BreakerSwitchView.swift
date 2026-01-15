//
//  BreakerSwitchView.swift
//  RockYou
//
//  3D breaker switch for dpad unlock mechanism.
//  Uses RealityView (iOS 18+ / macOS 15+) for cross-platform 3D rendering.
//

import RealityKit
import SwiftUI

// MARK: - View

struct BreakerSwitchView: View {
  /// 0.0 = down/locked, 1.0 = up/unlocked
  var progress: CGFloat = 0.0
  /// Additional camera yaw (degrees) applied on top of `BreakerSceneConfig.cameraYawDegrees`.
  /// Used to orbit the camera during the unlock drag without touching the lever transform.
  var cameraYawDegreesOffset: Float = 0
  /// Called once after the RealityView has loaded and added the model entity.
  var onReady: (() -> Void)? = nil

  @State private var leverEntity: Entity?
  @State private var modelValidationError: String?
  @State private var cameraAnchor: AnchorEntity?
  @State private var camera: PerspectiveCamera?
  @State private var didNotifyReady = false

  var body: some View {
    RealityView { content in
      // Add camera + lighting (shared rig)
      let camAnchor = makeBreakerCameraAnchor()
      content.add(camAnchor)
      cameraAnchor = camAnchor
      camera = camAnchor.children.compactMap { $0 as? PerspectiveCamera }.first
      content.add(makeBreakerLightAnchor())

      // Debug: Add XYZ axes at origin (where model is)
      if let axes = makeDebugAxes() {
        content.add(axes)
      }

      // Load the breaker switch model (from cache)
      do {
        let entity = try await BreakerModelCache.shared.loadModel()
        content.add(entity)
        leverEntity = prepareBreakerEntityForDisplay(entity)

        if !didNotifyReady {
          didNotifyReady = true
          onReady?()
        }

        // Set initial rotation (so it renders immediately, not waiting for first progress change)
        if let lever = leverEntity {
          let angle = BreakerSceneConfig.computeLeverAngle(progress: progress)
          lever.transform.rotation = simd_quatf(
            angle: angle, axis: BreakerSceneConfig.leverRotationAxis)
        }

        // Validate model is clean (sets error if garbage found)
        modelValidationError = validateBreakerModelIsClean(entity)
      } catch {
        Log.error("BreakerSwitch", "Failed to load model: \(error)")
      }
    } update: { content in
      guard let lever = leverEntity else { return }

      // Update lever rotation based on current progress
      let angle = BreakerSceneConfig.computeLeverAngle(progress: progress)
      lever.transform.rotation = simd_quatf(
        angle: angle, axis: BreakerSceneConfig.leverRotationAxis)

      // Update camera orbit yaw (if we captured the camera from the rig).
      if let camera, let cameraAnchor {
        let yawDegrees = BreakerSceneConfig.cameraYawDegrees + cameraYawDegreesOffset
        let yawRadians = yawDegrees * .pi / 180
        let distance = BreakerSceneConfig.cameraDistance
        camera.position = [
          sin(yawRadians) * distance,
          0,
          cos(yawRadians) * distance,
        ]
        camera.look(
          at: BreakerSceneConfig.position, from: camera.position, relativeTo: cameraAnchor)
      }
    }
    .debugCrashAlert(title: "USDZ Model Validation", message: $modelValidationError)
  }
}

// MARK: - Preview

#Preview("Static States") {
  ZStack {
    Color.white.ignoresSafeArea()

    VStack(spacing: 40) {
      VStack(spacing: 8) {
        Text("Locked (progress = 0.0)")
          .foregroundColor(.black)
          .font(.caption)
        BreakerSwitchView(progress: 0.0)
          .frame(width: 200, height: 200)
          .border(Color.gray)
      }

      VStack(spacing: 8) {
        Text("Unlocked (progress = 1.0)")
          .foregroundColor(.black)
          .font(.caption)
        BreakerSwitchView(progress: 1.0)
          .frame(width: 200, height: 200)
          .border(Color.gray)
      }
    }
  }
}

#Preview("Interactive") {
  struct InteractiveSwitchPreview: View {
    @State private var progress: CGFloat = 0.0

    var body: some View {
      ZStack {
        Color.white.ignoresSafeArea()

        VStack(spacing: 30) {
          BreakerSwitchView(progress: progress)
            .frame(width: 250, height: 250)
            .border(Color.gray)

          VStack(spacing: 12) {
            Text("Progress: \(Int(progress * 100))%")
              .foregroundColor(.black)
              .font(.title2)
              .monospacedDigit()

            Slider(value: $progress, in: 0...1)
              .padding(.horizontal, 40)
          }
        }
      }
    }
  }

  return InteractiveSwitchPreview()
}
