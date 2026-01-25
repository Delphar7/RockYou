// MetalDebugView.swift
// RockYou
//
// Reusable debug view for Metal/RealityKit playground scenes.
// Handles camera, lighting, controls, and interaction boilerplate.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

// MARK: - Playground Engine Protocol

/// Protocol for engines that can be used with MetalDebugView.
@MainActor
protocol PlaygroundEngine: AnyObject, Observable {
  var fragmentCount: Int { get }
  var domeRadius: Double { get }
  var showDpadTexture: Bool { get }

  func toShatterConfig() -> DomeShatterConfig

  /// Start the simulation. Called when the RealityView is created.
  func startSimulation(
    gpuShatterSim: DomeShatterGPU,
    in anchor: AnchorEntity,
    cameraPosition: SIMD3<Float>
  )
}

// MARK: - Metal Debug View

/// Generic debug view for Metal playground scenes.
/// Handles all the boilerplate: camera, lighting, controls, mouse interaction.
struct MetalDebugView<Engine: PlaygroundEngine>: View {
  @State var engine: Engine
  let config: [PropertyConfig<Engine>]
  var timeRange: ClosedRange<Double> = 0...10.0
  let makeDefaultEngine: () -> Engine

  @StateObject private var gpuShatterSim = DomeShatterGPU()

  @State private var currentTime: Double = 0
  @State private var subFrame: Double = 0
  @State private var isPlaying: Bool = false

  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 1.2

  @State private var restartID = UUID()

  /// UserDefaults key based on engine type name
  private var configKey: String { "PlaygroundConfig.\(String(describing: Engine.self))" }
  private static var cameraKey: String { "PlaygroundCamera" }

  // Default camera values
  private static var defaultYaw: Double { 45 }
  private static var defaultPitch: Double { 35 }
  private static var defaultDistance: Double { 1.2 }

  var body: some View {
    HSplitView {
      // Canvas
      MetalCanvas(
        engine: engine,
        gpuShatterSim: gpuShatterSim,
        effectiveTime: Float(currentTime + subFrame * (1.0 / 60.0)),
        yawDegrees: Float(yawDegrees),
        pitchDegrees: Float(pitchDegrees),
        cameraDistance: Float(cameraDistance)
      )
      .id(restartID)
      .frame(minWidth: 400, minHeight: 400)
      .overlay {
        CameraEventCapture(
          distance: $cameraDistance,
          yawDegrees: $yawDegrees,
          pitchDegrees: $pitchDegrees
        )
      }

      // Controls
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          GroupBox("Playback") {
            AnimationScrubber(
              timeRange: timeRange,
              frameRate: 60,
              currentTime: $currentTime,
              subFrameProgress: $subFrame,
              isPlaying: $isPlaying
            )
          }

          GroupBox("Status") {
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
              Button("Reset") {
                PropertyConfig<Engine>.clear(key: configKey)
                UserDefaults.standard.removeObject(forKey: Self.cameraKey)
                engine = makeDefaultEngine()
                yawDegrees = Self.defaultYaw
                pitchDegrees = Self.defaultPitch
                cameraDistance = Self.defaultDistance
                gpuShatterSim.stop()
                currentTime = 0
                subFrame = 0
                isPlaying = false
                restartID = UUID()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
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
            if allGone { isPlaying = false }
          }
          .onChange(of: isPlaying) { _, playing in
            // If user hits play while all fragments are gone, restart from beginning
            if playing && gpuShatterSim.allFragmentsGone {
              gpuShatterSim.stop()
              currentTime = 0
              subFrame = 0
              restartID = UUID()
            }
          }

          GroupBox("Configuration") {
            ConfigPanel(engine: engine, config: config, width: 240)
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
    .onAppear {
      PropertyConfig<Engine>.load(engine, config: config, key: configKey)
      loadCamera()
    }
    .onChange(of: restartID) { _, _ in
      // Save config whenever simulation restarts (captures any config changes)
      PropertyConfig<Engine>.save(engine, config: config, key: configKey)
      saveCamera()
    }
  }

  // MARK: - Camera Persistence

  private func saveCamera() {
    let dict: [String: Double] = [
      "yaw": yawDegrees,
      "pitch": pitchDegrees,
      "distance": cameraDistance,
    ]
    UserDefaults.standard.set(dict, forKey: Self.cameraKey)
  }

  private func loadCamera() {
    guard let dict = UserDefaults.standard.dictionary(forKey: Self.cameraKey) else { return }
    if let yaw = dict["yaw"] as? Double { yawDegrees = yaw }
    if let pitch = dict["pitch"] as? Double { pitchDegrees = pitch }
    if let distance = dict["distance"] as? Double { cameraDistance = distance }
  }
}

// MARK: - Metal Canvas

/// Generic RealityKit canvas for playground scenes.
private struct MetalCanvas<Engine: PlaygroundEngine>: View {
  var engine: Engine
  @ObservedObject var gpuShatterSim: DomeShatterGPU
  let effectiveTime: Float
  let yawDegrees: Float
  let pitchDegrees: Float
  let cameraDistance: Float

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var backdropEntity: Entity?

  var body: some View {
    RealityView { content in
      // Camera setup
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

      // Simulation anchor
      let anchor = AnchorEntity(world: .zero)
      content.add(anchor)

      // Start simulation (engine-specific)
      engine.startSimulation(gpuShatterSim: gpuShatterSim, in: anchor, cameraPosition: pos)

    } update: { _ in
      let camPos = PlaygroundCamera.position(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
      if let camera, let cameraAnchor {
        camera.position = camPos
        camera.look(at: .zero, from: camPos, relativeTo: cameraAnchor)
      }

      backdropEntity?.isEnabled = engine.showDpadTexture

      if gpuShatterSim.isActive {
        gpuShatterSim.setTime(effectiveTime)
        gpuShatterSim.updateCamera(position: camPos)
      }
    }
    .background(Color.black.opacity(0.9))
  }
}
