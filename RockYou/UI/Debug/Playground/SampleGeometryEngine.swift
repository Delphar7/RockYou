// SampleGeometryEngine.swift
// RockYou
//
// Example ConfigurableEngine demonstrating the pattern.
// This file can be moved to RockYou/UI/ when ready for production.
// The same code works in both debug panes and production.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

/// Sample geometry engine demonstrating ConfigurableEngine pattern.
///
/// In Debug: EngineConfigPanel auto-generates sliders/toggles for experimentation.
/// In Production: Just set properties directly - `engine.radius = 0.5`
@Observable
final class SampleGeometryEngine: ConfigurableEngine {

  // MARK: - Configurable Properties

  var radius: Double = 0.5
  var segments: Int = 12
  var rotation: Double = 0
  var showOutline: Bool = true
  var fillColor: Color = .blue

  // MARK: - Property Descriptors (metadata for UI generation)

  static let propertyDescriptors: [String: PropertyDescriptor] = [
    "radius": .init("Radius", .slider(min: 0.1, max: 1.0, step: 0.01)),
    "segments": .init("Segments", .intStepper(min: 3, max: 32, step: 1)),
    "rotation": .init("Rotation", .slider(min: 0, max: .pi * 2, step: 0.01)),
    "showOutline": .init("Show Outline", .toggle),
    "fillColor": .init("Fill Color", .color),
  ]

  // MARK: - Dynamic Accessors (required by protocol)

  func getValue(forKey key: String) -> Any? {
    switch key {
    case "radius": return radius
    case "segments": return segments
    case "rotation": return rotation
    case "showOutline": return showOutline
    case "fillColor": return fillColor
    default: return nil
    }
  }

  func setValue(_ value: Any, forKey key: String) {
    switch key {
    case "radius": if let v = value as? Double { radius = v }
    case "segments": if let v = value as? Int { segments = v }
    case "rotation": if let v = value as? Double { rotation = v }
    case "showOutline": if let v = value as? Bool { showOutline = v }
    case "fillColor": if let v = value as? Color { fillColor = v }
    default: break
    }
  }

  // MARK: - Engine Logic (the actual algorithm)

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

// MARK: - Canvas View (can be used in debug or production)

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

// MARK: - Debug View (uses EngineConfigPanel)

/// Debug harness - demonstrates auto-generated UI
struct SampleGeometryDebugView: View {
  @State private var engine = SampleGeometryEngine()

  var body: some View {
    HSplitView {
      SampleGeometryCanvas(engine: engine)
        .frame(minWidth: 400, minHeight: 400)

      EngineConfigPanel(engine: engine)
    }
  }
}

#Preview("Sample Geometry") {
  SampleGeometryDebugView()
    .frame(width: 750, height: 500)
}
