// RealityDebugView.swift
// RockYou/UI/Debug/Playground
//
// Generic debug view wrapper for SceneView + SceneContent architecture.
// Provides time scrubbing, camera controls, and config panel.
// Replaces MetalDebugView for migrated engines.

import RealityKit
import SwiftUI

// MARK: - Content Engine Protocol

/// Protocol for engines that create SceneContent.
/// Simpler than PlaygroundEngine - just creates content, no DomeShatterGPU dependency.
@MainActor
protocol ContentEngine: AnyObject, Observable {
  associatedtype Content: SceneContent

  /// Create the scene content. Called once when view appears.
  func makeContent() -> Content

  /// Time range for animation scrubber
  static var timeRange: ClosedRange<Double> { get }
}

// MARK: - Reality Debug View

/// Debug view for SceneContent-based engines.
/// Wraps SceneView with playback controls, camera orbit, and config panel.
struct RealityDebugView<Engine: ContentEngine>: View {
  @State var engine: Engine
  let config: [PropertyConfig<Engine>]
  let makeDefaultEngine: () -> Engine

  @State private var content: Engine.Content?
  @State private var currentTime: Double = 0
  @State private var subFrame: Double = 0
  @State private var isPlaying: Bool = false

  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 1.2

  @State private var restartID = UUID()
  @State private var softRestartID = UUID()
  @State private var configChangeID = UUID()
  @State private var autoRestart: Bool = true

  private var effectiveTime: Float {
    Float(currentTime + subFrame * (1.0 / 60.0))
  }

  private var cameraPosition: SIMD3<Float> {
    PlaygroundCamera.position(
      yaw: Float(yawDegrees),
      pitch: Float(pitchDegrees),
      distance: Float(cameraDistance)
    )
  }

  var body: some View {
    HSplitView {
      // Scene canvas
      Group {
        if let content {
          SceneView(
            content: content,
            time: effectiveTime,
            cameraPosition: cameraPosition,
            contentID: softRestartID
          )
        } else {
          Color.black
        }
      }
      .id(restartID)
      .frame(minWidth: 400, minHeight: 400)
      .overlay {
        CameraEventCapture(
          distance: $cameraDistance,
          yawDegrees: $yawDegrees,
          pitchDegrees: $pitchDegrees
        )
      }

      // Controls sidebar
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          GroupBox("Playback") {
            AnimationScrubber(
              timeRange: Engine.timeRange,
              frameRate: 60,
              currentTime: $currentTime,
              subFrameProgress: $subFrame,
              isPlaying: $isPlaying
            )
          }

          GroupBox("Actions") {
            HStack {
              Spacer()
              Button("Reset") {
                engine = makeDefaultEngine()
                restart()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)

              Button("Restart") {
                restart()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }

          GroupBox("Configuration") {
            ConfigPanel(
              engine: engine, config: config, width: 240,
              onChanged: {
                configChangeID = UUID()
              }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Auto Restart", isOn: $autoRestart)
              .toggleStyle(.checkbox)
              .padding(.top, 1)
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
      if content == nil {
        content = engine.makeContent()
      }
    }
    .onChange(of: configChangeID) { _, _ in
      // Auto-restart on config change (soft restart - no screen flicker)
      if autoRestart {
        currentTime = 0
        subFrame = 0
        content = engine.makeContent()
        softRestartID = UUID()
      }
    }
  }

  private func restart() {
    currentTime = 0
    subFrame = 0
    isPlaying = false
    content = engine.makeContent()
    restartID = UUID()
  }
}
