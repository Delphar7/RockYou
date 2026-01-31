// SceneView.swift
// RockYou/UI/Dome
//
// Generic RealityView wrapper providing camera, lighting, and time-based updates.
// Content is provided via SceneContent protocol - the scene doesn't know what it's rendering.

import RealityKit
import SwiftUI

// MARK: - Scene Content Protocol

/// Protocol for content that can be hosted in a SceneView.
/// Content provides its entity and knows how to update itself based on time and camera.
@MainActor
protocol SceneContent: AnyObject {
  /// The root entity for this content. Added to the scene on setup.
  var entity: Entity { get }

  /// Called each frame with current time and camera position.
  /// Content should update its material uniforms, animations, etc.
  func update(time: Float, cameraPosition: SIMD3<Float>)

  /// Whether the animation has completed (all fragments gone, etc.)
  /// Default implementation returns false.
  var isComplete: Bool { get }
}

extension SceneContent {
  var isComplete: Bool { false }
}

// MARK: - Scene View

/// Generic 3D scene view with camera, lighting, and content.
/// The scene handles all RealityKit boilerplate - content just provides an entity.
struct SceneView: View {
  let content: SceneContent
  var time: Float
  var cameraPosition: SIMD3<Float>

  /// Camera field of view in degrees
  var cameraFOV: Float = 50

  /// Lighting intensity multiplier
  var lightingIntensity: Float = 1.0

  /// Change this ID to trigger a soft restart (replace content without view recreation)
  var contentID: UUID = UUID()

  @State private var camera: PerspectiveCamera?
  @State private var cameraAnchor: AnchorEntity?
  @State private var contentAnchor: AnchorEntity?
  @State private var lastContentID: UUID?

  var body: some View {
    RealityView { ctx in
      // Camera setup
      let camAnchor = AnchorEntity(world: .zero)
      let cam = PerspectiveCamera()
      cam.camera.fieldOfViewInDegrees = cameraFOV
      cam.position = cameraPosition
      cam.look(at: .zero, from: cameraPosition, relativeTo: camAnchor)
      camAnchor.addChild(cam)
      ctx.add(camAnchor)
      camera = cam
      cameraAnchor = camAnchor

      // Lighting - key light + fill
      let lightAnchor = AnchorEntity(world: .zero)

      let key = DirectionalLight()
      key.light.intensity = 2600 * lightingIntensity
      key.look(at: .zero, from: [0.8, 0.6, 0.5], relativeTo: nil)
      lightAnchor.addChild(key)

      let fill = PointLight()
      fill.light.intensity = 520 * lightingIntensity
      fill.position = [0.4, 0.3, 0.2]
      lightAnchor.addChild(fill)

      ctx.add(lightAnchor)

      // Content anchor - allows swapping content without recreating view
      let anchor = AnchorEntity(world: .zero)
      anchor.addChild(content.entity)
      ctx.add(anchor)
      contentAnchor = anchor
      lastContentID = contentID

      // Initial update
      content.update(time: time, cameraPosition: cameraPosition)

    } update: { _ in
      // Update camera
      if let camera, let cameraAnchor {
        camera.position = cameraPosition
        camera.look(at: .zero, from: cameraPosition, relativeTo: cameraAnchor)
      }

      // Check for content swap (soft restart)
      if contentID != lastContentID, let anchor = contentAnchor {
        lastContentID = contentID
        // Remove old content
        for child in anchor.children {
          child.removeFromParent()
        }
        // Add new content
        anchor.addChild(content.entity)
      }

      // Update content
      content.update(time: time, cameraPosition: cameraPosition)
    }
  }
}
