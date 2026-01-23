// ParticleExplosionDebugView.swift
// RockYou
//
// Debug view for dome particle explosion (shatter) effect.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

struct ParticleExplosionDebugView: View {
  @State private var engine = ParticleExplosionEngine()
  @StateObject private var gpuShatterSim = DomeShatterGPU()

  // Animation state (controlled by AnimationScrubber, like BloomingFlower)
  @State private var currentTime: Double = 0
  @State private var subFrame: Double = 0
  @State private var isPlaying: Bool = false

  // Camera
  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 1.2

  // Restart trigger
  @State private var restartID = UUID()

  var body: some View {
    HSplitView {
      // 3D Canvas - pass effective time like BloomingFlower passes aperture
      ParticleExplosionCanvas(
        engine: engine,
        gpuShatterSim: gpuShatterSim,
        effectiveTime: Float(currentTime + subFrame * (1.0 / 60.0)),
        yawDegrees: Float(yawDegrees),
        pitchDegrees: Float(pitchDegrees),
        cameraDistance: Float(cameraDistance)
      )
      .id(restartID)
      .frame(minWidth: 400, minHeight: 400)

      // Controls
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          GroupBox("Playback") {
            AnimationScrubber(
              timeRange: 0...10.0,
              frameRate: 60,
              currentTime: $currentTime,
              subFrameProgress: $subFrame,
              isPlaying: $isPlaying
            )
          }

          GroupBox("Fragments") {
            HStack {
              Text("Count")
              Spacer()
              TextField("", value: $engine.fragmentCount, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            HStack {
              if gpuShatterSim.isActive {
                if gpuShatterSim.allFragmentsGone {
                  Text("All fragments gone")
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                  Text("\(gpuShatterSim.fragmentCount) active")
                    .font(.caption)
                    .foregroundStyle(.green)
                }
              }
              Spacer()
              Button("Restart") {
                gpuShatterSim.stop()
                currentTime = 0
                subFrame = 0
                isPlaying = false
                restartID = UUID()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
          .onChange(of: gpuShatterSim.allFragmentsGone) { _, allGone in
            if allGone {
              isPlaying = false
            }
          }
          .onChange(of: isPlaying) { _, playing in
            // Restart from beginning if playing after animation ended
            if playing && gpuShatterSim.allFragmentsGone {
              gpuShatterSim.stop()
              currentTime = 0
              subFrame = 0
              restartID = UUID()
            }
          }

          GroupBox("Physics") {
            EngineConfigPanel(engine: engine, width: 240)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          GroupBox("Camera") {
            PlaygroundCameraControls(
              yawDegrees: $yawDegrees,
              pitchDegrees: $pitchDegrees,
              distance: $cameraDistance
            )
          }

          Spacer()
        }
        .padding()
      }
      .frame(width: 280)
    }
  }
}

// MARK: - Canvas

private struct ParticleExplosionCanvas: View {
  var engine: ParticleExplosionEngine
  @ObservedObject var gpuShatterSim: DomeShatterGPU
  let effectiveTime: Float
  let yawDegrees: Float
  let pitchDegrees: Float
  let cameraDistance: Float

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var fragmentsAnchor: AnchorEntity?
  @State private var backdropEntity: Entity?

  var body: some View {
    RealityView { content in
      // Camera
      let camAnchor = AnchorEntity(world: .zero)
      let cam = PerspectiveCamera()
      cam.camera.fieldOfViewInDegrees = 50
      let pos = PlaygroundCamera.position(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
      cam.position = pos
      cam.look(at: .zero, from: pos, relativeTo: camAnchor)
      camAnchor.addChild(cam)
      content.add(camAnchor)
      camera = cam
      cameraAnchor = camAnchor

      // Lighting
      content.add(PlaygroundScene.makeLighting())

      // Backdrop
      if let backdrop = PlaygroundScene.makeBackdropEntity() {
        backdrop.position = [0, -0.01, 0]
        backdrop.scale = [Float(engine.domeRadius) * 2, 1, Float(engine.domeRadius) * 2]
        backdrop.isEnabled = engine.showDpadTexture
        content.add(backdrop)
        backdropEntity = backdrop
      }

      // Fragments anchor
      let anchor = AnchorEntity(world: .zero)
      content.add(anchor)
      fragmentsAnchor = anchor

      // Start simulation immediately (like BloomingFlower calls regenerateBlades in make)
      var waveOrigin: SIMD3<Float>? = nil
      if engine.waveEnabled {
        waveOrigin = simd_normalize(pos) * Float(engine.domeRadius) * 0.8
      }

      gpuShatterSim.start(
        fragmentCount: engine.fragmentCount,
        radius: Float(engine.domeRadius),
        in: anchor,
        config: engine.toShatterConfig(),
        waveOrigin: waveOrigin,
        waveSpeed: Float(engine.waveSpeed),
        cameraPosition: pos
      )

    } update: { _ in
      // Camera
      let camPos = PlaygroundCamera.position(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
      if let camera, let cameraAnchor {
        camera.position = camPos
        camera.look(at: .zero, from: camPos, relativeTo: cameraAnchor)
      }

      // Backdrop
      backdropEntity?.isEnabled = engine.showDpadTexture

      // Update time and camera (like BloomingFlower updates aperture)
      if gpuShatterSim.isActive {
        gpuShatterSim.setTime(effectiveTime)
        gpuShatterSim.updateCamera(position: camPos)
      }
    }
    .background(Color.black.opacity(0.9))
  }
}

#Preview("Particle Explosion") {
  ParticleExplosionDebugView()
    .frame(width: 900, height: 700)
}
