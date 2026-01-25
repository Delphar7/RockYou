// SampleGeometryEngine.swift
// RockYou
//
// Example engine demonstrating the PropertyConfig pattern.
// This file can be moved to RockYou/UI/ when ready for production.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Sample geometry engine demonstrating PropertyConfig pattern.
///
/// In Debug: ConfigPanel auto-generates sliders/toggles from the config array.
/// In Production: Just set properties directly - `engine.radius = 0.5`
@Observable
final class SampleGeometryEngine {

  // MARK: - Properties

  var radius: Double = 0.5
  var segments: Int = 12
  var rotation: Double = 0
  var showOutline: Bool = true
  var fillColor: Color = .blue

  // MARK: - Config (single source of truth for UI)

  static let config: [PropertyConfig<SampleGeometryEngine>] = [
    .slider(\.radius, "Radius", 0.1...1.0, step: 0.01),
    .stepper(\.segments, "Segments", 3...32, step: 1),
    .slider(\.rotation, "Rotation", 0...(.pi * 2), step: 0.01),
    .toggle(\.showOutline, "Show Outline"),
    .color(\.fillColor, "Fill Color"),
  ]

  // MARK: - Engine Logic

  /// Generate polygon points - this is what production code cares about
  func generatePolygonPoints(in size: CGSize) -> [CGPoint] {
    let centerX = size.width / 2
    let centerY = size.height / 2
    let r = min(size.width, size.height) * radius / 2
    let angleStep = (2.0 * .pi) / Double(segments)

    var points: [CGPoint] = []
    for i in 0..<segments {
      let angle = rotation + Double(i) * angleStep - .pi / 2
      let x = centerX + r * cos(angle)
      let y = centerY + r * sin(angle)
      points.append(CGPoint(x: x, y: y))
    }
    return points
  }
}

// MARK: - Canvas View

/// Renders the geometry - works the same whether engine is being tweaked or in production
struct SampleGeometryCanvas: View {
  var engine: SampleGeometryEngine

  var body: some View {
    Canvas { context, size in
      let points = engine.generatePolygonPoints(in: size)
      guard points.count >= 3 else { return }

      var path = Path()
      path.move(to: points[0])
      for point in points.dropFirst() {
        path.addLine(to: point)
      }
      path.closeSubpath()

      context.fill(path, with: .color(engine.fillColor.opacity(0.5)))

      if engine.showOutline {
        context.stroke(path, with: .color(engine.fillColor), lineWidth: 2)
      }
    }
    .background(Color.black.opacity(0.1))
  }
}

// MARK: - Debug View

/// Debug harness - demonstrates auto-generated UI
struct SampleGeometryDebugView: View {
  @State private var engine = SampleGeometryEngine()

  var body: some View {
    HSplitView {
      SampleGeometryCanvas(engine: engine)
        .frame(minWidth: 400, minHeight: 400)

      ConfigPanel(engine: engine, config: SampleGeometryEngine.config)
    }
  }
}

#Preview("Sample Geometry") {
  SampleGeometryDebugView()
    .frame(width: 750, height: 500)
}
