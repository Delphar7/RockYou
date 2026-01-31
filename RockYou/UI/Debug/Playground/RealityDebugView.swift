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
/// Persists engine config and camera position to UserDefaults.
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

  // Persistence keys
  private var configKey: String { "PlaygroundConfig.\(String(describing: Engine.self))" }
  private static var cameraKey: String { "PlaygroundCamera" }

  // Default camera values
  private static var defaultYaw: Double { 45 }
  private static var defaultPitch: Double { 35 }
  private static var defaultDistance: Double { 1.2 }

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

          GroupBox("Status") {
            HStack {
              if let content {
                if content.isComplete {
                  Text("All fragments gone")
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                  Text("Active")
                    .font(.caption)
                    .foregroundStyle(.green)
                }
              }
              Spacer()
              Button("Reset") {
                // Clear persisted state and restore defaults
                PropertyConfig<Engine>.clear(key: configKey)
                UserDefaults.standard.removeObject(forKey: Self.cameraKey)
                engine = makeDefaultEngine()
                yawDegrees = Self.defaultYaw
                pitchDegrees = Self.defaultPitch
                cameraDistance = Self.defaultDistance
                restart()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)

              Button("Restart") {
                // Save current config, then restart
                saveState()
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
      // Load persisted config and camera
      PropertyConfig<Engine>.load(engine, config: config, key: configKey)
      loadCamera()
      if content == nil {
        content = engine.makeContent()
      }
    }
    .onChange(of: configChangeID) { _, _ in
      // Auto-restart on config change (soft restart - no screen flicker)
      // Preserve current time so user can see effect of config changes at current position
      if autoRestart {
        content = engine.makeContent()
        softRestartID = UUID()
      }
    }
    .onChange(of: currentTime) { _, _ in
      // Check if animation completed - stop playing
      if isPlaying, let content, content.isComplete {
        isPlaying = false
      }
    }
    .onChange(of: isPlaying) { _, playing in
      // If user hits play while complete, restart from beginning
      if playing, let content, content.isComplete {
        restart()
        isPlaying = true  // restart() sets isPlaying = false, so re-enable
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

  // MARK: - Persistence

  private func saveState() {
    PropertyConfig<Engine>.save(engine, config: config, key: configKey)
    saveCamera()
  }

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
