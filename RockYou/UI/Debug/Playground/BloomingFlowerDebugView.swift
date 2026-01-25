// BloomingFlowerDebugView.swift
// RockYou
//
// Debug view for dome iris "blooming flower" blade animation.
// Uses BloomingFlowerEngine for geometry + AnimationScrubber for aperture.
// macOS-only (excluded from iOS via build settings)

import RealityKit
import SwiftUI

struct BloomingFlowerDebugView: View {
  @State private var engine = BloomingFlowerEngine()

  // Animation state (not part of engine - controlled by scrubber)
  @State private var aperture: Double = 0
  @State private var subFrame: Double = 0
  @State private var isPlaying: Bool = false

  // Camera state (separate from engine)
  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 1.2

  var body: some View {
    HSplitView {
      // 3D View
      // Aperture + subframe interpolation: subFrame (0-1) * frame duration (1/60)
      BloomingFlowerRealityView(
        engine: engine,
        aperture: Float(aperture + subFrame * (1.0 / 60.0)),
        yawDegrees: Float(yawDegrees),
        pitchDegrees: Float(pitchDegrees),
        cameraDistance: Float(cameraDistance)
      )
      .frame(minWidth: 400, minHeight: 400)

      // Controls
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Aperture animation
          GroupBox("Aperture") {
            AnimationScrubber(
              timeRange: 0...1.0,
              frameRate: 60,
              currentTime: $aperture,
              subFrameProgress: $subFrame,
              isPlaying: $isPlaying
            )

            // Quick presets
            HStack {
              Button("0%") { aperture = 0 }
              Button("25%") { aperture = 0.25 }
              Button("50%") { aperture = 0.5 }
              Button("75%") { aperture = 0.75 }
              Button("100%") { aperture = 1.0 }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }

          // Engine config (auto-generated)
          GroupBox("Blade Configuration") {
            ConfigPanel(engine: engine, config: BloomingFlowerEngine.config, width: 240)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          // Camera controls
          GroupBox("Camera") {
            PlaygroundCameraControls(
              yawDegrees: $yawDegrees,
              pitchDegrees: $pitchDegrees,
              distance: $cameraDistance
            )
          }

          // Reset
          Button("Reset All") {
            engine.bladeCount = 10
            engine.bladeCoverage = 0.85
            engine.bladeOverlap = 0.02
            engine.showDpadTexture = true
            engine.showMetalLayer = true
            aperture = 0
            subFrame = 0
            isPlaying = false
            yawDegrees = 45
            pitchDegrees = 35
            cameraDistance = 1.2
          }
          .buttonStyle(.bordered)

          Spacer()
        }
        .padding()
      }
      .frame(width: 280)
    }
  }
}

// MARK: - RealityKit View

private struct BloomingFlowerRealityView: View {
  var engine: BloomingFlowerEngine
  let aperture: Float
  let yawDegrees: Float
  let pitchDegrees: Float
  let cameraDistance: Float

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var bladesAnchor: AnchorEntity?
  @State private var bladeAnchors: [Entity] = []
  @State private var backdropEntity: Entity?
  @State private var lastBladeCount: Int = 0

  private let maxRotationRadians: Float = 1.5
  private let domeRadius: Float = 0.5

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

      // DPad backdrop
      if let backdrop = PlaygroundScene.makeBackdropEntity() {
        backdrop.position = [0, -0.01, 0]
        backdrop.scale = [domeRadius * 2, 1, domeRadius * 2]
        backdrop.isEnabled = engine.showDpadTexture
        content.add(backdrop)
        backdropEntity = backdrop
      }

      // Blades anchor
      let bladeAnchor = AnchorEntity(world: .zero)
      content.add(bladeAnchor)
      bladesAnchor = bladeAnchor

      regenerateBlades()
      lastBladeCount = engine.bladeCount

    } update: { _ in
      // Update camera
      let camPos = PlaygroundCamera.position(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
      if let camera, let cameraAnchor {
        camera.position = camPos
        camera.look(at: .zero, from: camPos, relativeTo: cameraAnchor)
      }

      // Update display options
      backdropEntity?.isEnabled = engine.showDpadTexture

      for pivotAnchor in bladeAnchors {
        for child in pivotAnchor.children {
          if child.name.contains("_metal") {
            child.isEnabled = engine.showMetalLayer
          }
        }
      }

      // Regenerate blades if count changed
      if engine.bladeCount != lastBladeCount {
        regenerateBlades()
        lastBladeCount = engine.bladeCount
      }

      // Update blade rotations for aperture
      updateBladeRotations()
    }
    .background(Color.black.opacity(0.9))
  }

  private func regenerateBlades() {
    guard let bladesAnchor else { return }

    // Remove existing
    for child in bladesAnchor.children {
      child.removeFromParent()
    }
    bladeAnchors = []

    let config = engine.toMeshConfig(domeRadius: domeRadius)
    let glassMaterial = DomeBladeMeshGenerator.makeGlassMaterial()
    let metalMaterial = DomeBladeMeshGenerator.makeMetalMaterial()

    let N = config.bladeCount
    let sectorAngle = (2 * Float.pi) / Float(N)

    for i in 0..<N {
      let baseAngle = Float(i) * sectorAngle

      let pivotAnchor = Entity()
      pivotAnchor.name = "BladePivot_\(i)"

      let pivotTheta = Float.pi / 2
      let pivotPhi = baseAngle
      let r = config.domeRadius
      let pivotPos = SIMD3<Float>(
        r * sin(pivotTheta) * cos(pivotPhi),
        r * cos(pivotTheta),
        r * sin(pivotTheta) * sin(pivotPhi)
      )
      pivotAnchor.position = pivotPos

      do {
        let mesh = try DomeBladeMeshGenerator.makeBladeSurfaceMesh(bladeIndex: i, config: config)

        let glassEntity = ModelEntity(mesh: mesh, materials: [glassMaterial])
        glassEntity.name = "Blade_\(i)_glass"
        glassEntity.position = -pivotPos

        let metalEntity = ModelEntity(mesh: mesh, materials: [metalMaterial])
        metalEntity.name = "Blade_\(i)_metal"
        metalEntity.position = -pivotPos
        metalEntity.isEnabled = engine.showMetalLayer

        pivotAnchor.addChild(glassEntity)
        pivotAnchor.addChild(metalEntity)
      } catch {
        print("Failed to create blade mesh \(i): \(error)")
      }

      bladesAnchor.addChild(pivotAnchor)
      bladeAnchors.append(pivotAnchor)
    }

    updateBladeRotations()
  }

  private func updateBladeRotations() {
    let N = bladeAnchors.count
    guard N > 0 else { return }

    let sectorAngle = (2 * Float.pi) / Float(N)
    let t = aperture * aperture * (3 - 2 * aperture)  // smoothstep

    for (i, pivotAnchor) in bladeAnchors.enumerated() {
      let baseAngle = Float(i) * sectorAngle
      let axisAngle = baseAngle + Float.pi / 2
      let axis = SIMD3<Float>(cos(axisAngle), 0, sin(axisAngle))
      let rotation = -t * maxRotationRadians

      pivotAnchor.orientation = simd_quatf(angle: rotation, axis: axis)
    }
  }
}

#Preview("Blooming Flower") {
  BloomingFlowerDebugView()
    .frame(width: 900, height: 650)
}
