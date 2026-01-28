// IrisEngine.swift
// RockYou/UI/Debug/Playground
//
// Playground engine for iris mechanism animation.
// Implements ContentEngine for RealityDebugView.

import RealityKit
import SwiftUI

/// Playground engine for iris mechanism effect.
/// Uses IrisContent for rendering via the new SceneView architecture.
@Observable
final class IrisEngine: ContentEngine {
  typealias Content = IrisContent

  // MARK: - Config

  var config = IrisAnimationConfig()

  // MARK: - ContentEngine

  static let timeRange: ClosedRange<Double> = 0...8.0

  func makeContent() -> IrisContent {
    IrisContent(config: config)
  }

  // MARK: - PropertyConfig (UI Bindings)

  static let propertyConfig: [PropertyConfig<IrisEngine>] = [
    .intField(\.config.fragmentCount, "Fragment Count"),
    .slider(\.config.domeRadius, "Dome Radius", 0.2...1.0, step: 0.05),
    .stepper(\.config.bladeCount, "Blade Count", 4...24, step: 1),
    .slider(\.config.twistDegrees, "Twist", -180...180, step: 5),
    .slider(\.config.openDuration, "Open Duration", 1.0...10.0, step: 0.5),
    .toggle(\.config.showSeamRibbons, "Seam Ribbons"),
  ]
}
