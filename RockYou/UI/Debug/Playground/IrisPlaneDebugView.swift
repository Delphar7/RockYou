// IrisPlaneDebugView.swift
// RockYou/UI/Debug/Playground
//
// 3D visualizer for plane-sphere iris intersection geometry.
// Animates from closed to open with play controls.
// Shows all blade arcs to visualize the full iris aperture shape.

import Combine
import simd
import SwiftUI
import SceneKit

// MARK: - View

struct IrisPlaneDebugView: View {
  // Blade parameters
  @State private var tilt: Double = 0.3
  @State private var elevation: Double = 0.25
  @State private var bladeCount: Int = 8

  // Animation
  @State private var animationT: Double = 0.0
  @State private var isPlaying: Bool = false
  @State private var looping: Bool = false
  @State private var playbackSpeed: Double = 1.0

  // Display
  @State private var showAllBlades: Bool = true
  @State private var showFullCircle: Bool = true
  @State private var showPlane: Bool = true
  @State private var showNormals: Bool = false

  // Camera
  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 3.0

  private let domeRadius: Float = 1.0
  private let animationDuration: Double = 3.0  // seconds at 1x

  // MARK: - Computed Thresholds

  private var closedThreshold: Float {
    IrisPlaneAlgorithm.closedThreshold(
      bladeCount: bladeCount, radius: domeRadius, elevation: Float(elevation)
    )
  }

  /// Phase budget: fraction of T allocated to threshold sweep (phase 1).
  /// Matches kPhase1Fraction in IrisAlgorithm.h.
  private let phase1Fraction: Double = 2.0 / 3.0

  private var computedThreshold: Float {
    let closed = closedThreshold
    let t = Float(min(animationT, phase1Fraction) / phase1Fraction)  // 0...1 within phase 1
    // closedThreshold → -0.9R (through center, arcs concave toward Y-axis)
    let target: Float = -domeRadius * 0.9
    let raw = closed + t * (target - closed)
    // Compress the degenerate zone near 0: snap to ±ε
    let eps: Float = 0.03
    if abs(raw) < eps {
      return raw >= 0 ? eps : -eps
    }
    return raw
  }

  /// Critical elevation where all intersection circles drop below Y=0
  /// at the phase-1 endpoint threshold (-αR).
  /// Derived from: maxY = -αR·sin(E) + R·√(1-α²)·cos(E) = 0
  ///            → tan(E_crit) = √(1-α²) / α
  private var phase2TargetElevation: Float {
    let alpha: Float = 0.9  // |threshold/R| at end of phase 1
    let criticalElev = atan(sqrt(1.0 - alpha * alpha) / alpha)
    // Safety margin for near-tangent remnants and numerical tolerance
    let margin: Float = 5.0 * .pi / 180.0  // 5°
    return criticalElev + margin
  }

  /// Phase 2 (T > phase1Fraction): elevation ramp to computed critical target.
  /// LERPs over the phase 2 budget so it finishes exactly at T=1.0.
  private var computedElevation: Float {
    guard animationT > phase1Fraction else { return Float(elevation) }
    let base = Float(elevation)
    let target = phase2TargetElevation
    guard target > base else { return base }
    let phase2Duration = 1.0 - phase1Fraction
    let progress = Float(min((animationT - phase1Fraction) / phase2Duration, 1.0))
    return base + progress * (target - base)
  }

  var body: some View {
    HSplitView {
      // 3D SceneKit view
      IrisPlaneScene3DView(
        tilt: Float(tilt),
        elevation: computedElevation,
        threshold: computedThreshold,
        closedThreshold: closedThreshold,
        bladeCount: bladeCount,
        domeRadius: domeRadius,
        showAllBlades: showAllBlades,
        showFullCircle: showFullCircle,
        showPlane: showPlane,
        showNormals: showNormals,
        yawDegrees: Float(yawDegrees),
        pitchDegrees: Float(pitchDegrees),
        cameraDistance: Float(cameraDistance)
      )
      .overlay {
        CameraEventCapture(
          distance: $cameraDistance,
          yawDegrees: $yawDegrees,
          pitchDegrees: $pitchDegrees,
          distanceRange: 0.5...6.0
        )
      }
      .frame(minWidth: 500, minHeight: 400)

      // Controls
      controlsPanel
        .frame(width: 280)
    }
    .onReceive(
      Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    ) { _ in
      guard isPlaying else { return }
      animationT += playbackSpeed / (60.0 * animationDuration)
      if animationT >= 1.0 {
        if looping {
          animationT = 0.0
        } else {
          animationT = 1.0
          isPlaying = false
        }
      }
    }
  }

  // MARK: - Controls

  private var controlsPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox("Animation") {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("T:")
              Slider(value: $animationT, in: 0...1.0)
              Text("\(animationT, specifier: "%.3f")")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            }

            // Playback controls
            HStack(spacing: 8) {
              Button(action: {
                if animationT >= 1.0 { animationT = 0.0 }
                isPlaying.toggle()
              }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                  .frame(width: 20)
              }
              Button(action: { animationT = 0.0; isPlaying = false }) {
                Image(systemName: "backward.end.fill")
                  .frame(width: 20)
              }
              Toggle("Loop", isOn: $looping)
                .toggleStyle(.checkbox)

              Spacer()

              Picker("", selection: $playbackSpeed) {
                Text("0.25x").tag(0.25)
                Text("0.5x").tag(0.5)
                Text("1x").tag(1.0)
                Text("2x").tag(2.0)
              }
              .pickerStyle(.segmented)
              .frame(width: 160)
            }

            VStack(alignment: .leading, spacing: 2) {
              Text("Closed d: \(closedThreshold, specifier: "%.3f")")
              Text("Current d: \(computedThreshold, specifier: "%.3f")")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)

            if abs(computedThreshold) < 0.05 {
              Text("Near degenerate zone (d \u{2248} 0)")
                .font(.caption2).foregroundStyle(.red)
            }
          }
        }

        GroupBox("Blade Normal") {
          VStack(alignment: .leading) {
            HStack {
              Text("Tilt:")
              Slider(value: $tilt, in: -(Double.pi / 2)...(Double.pi / 2))
              Text("\(tilt * 180 / .pi, specifier: "%.1f")\u{00B0}")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            }

            HStack {
              Text("Elev:")
              Slider(value: $elevation, in: 0.05...(Double.pi / 2.2))
              Text("\(elevation * 180 / .pi, specifier: "%.1f")\u{00B0}")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
            }

            Stepper("Blades: \(bladeCount)", value: $bladeCount, in: 3...16)
          }
          .font(.caption)
        }

        GroupBox("Display") {
          VStack(alignment: .leading) {
            Toggle("Show all blade arcs", isOn: $showAllBlades)
            Toggle("Show cutting plane (blade 0)", isOn: $showPlane)
            Toggle("Show full intersection circle", isOn: $showFullCircle)
            Toggle("Show blade normals", isOn: $showNormals)
          }
        }

        GroupBox("Camera") {
          PlaygroundCameraControls(
            yawDegrees: $yawDegrees,
            pitchDegrees: $pitchDegrees,
            distance: $cameraDistance,
            distanceRange: 0.5...6.0
          )
        }

        GroupBox("Data") {
          dataReadout
        }

        Spacer()
      }
      .padding()
    }
  }

  private var dataReadout: some View {
    let elev = computedElevation
    let n = IrisPlaneAlgorithm.bladeNormal(
      index: 0, bladeCount: bladeCount,
      tilt: Float(tilt), elevation: elev
    )
    let R = domeRadius
    let d = computedThreshold
    let circleRadius: Float = abs(d) < R ? sqrt(R * R - d * d) : 0

    return VStack(alignment: .leading, spacing: 4) {
      Text("Blade 0 normal:")
        .font(.caption.bold())
      Text("  (\(n.x, specifier: "%.3f"), \(n.y, specifier: "%.3f"), \(n.z, specifier: "%.3f"))")

      Divider()
      Text("Plane: dot(Q, n) = \(d, specifier: "%.3f")")
      Text("Circle radius: \(circleRadius, specifier: "%.3f")")

      Divider()
      Text("cos(elev) = \(cos(elev), specifier: "%.3f")")
      Text("Max equatorial dot = \(R * cos(elev), specifier: "%.3f")")
      let canClear = R * cos(elev) >= d
      Text("Can clear equator: \(canClear ? "YES" : "NO")")
        .foregroundColor(canClear ? .green : .red)

      if animationT > phase1Fraction {
        Divider()
        Text("Phase 2: elevation sweep")
          .font(.caption.bold()).foregroundStyle(.orange)
        Text("Elev: \(elev * 180 / .pi, specifier: "%.1f")\u{00B0} → \(phase2TargetElevation * 180 / .pi, specifier: "%.1f")\u{00B0}")
      }

      Divider()
      Text("Arc concavity: \(d < 0 ? "toward center" : d > 0 ? "transitioning" : "---")")
        .foregroundColor(d < 0 ? .green : .secondary)
        .font(.caption.bold())
    }
    .font(.system(.caption, design: .monospaced))
  }
}

// MARK: - Algorithm Helpers

private enum IrisPlaneAlgorithm {
  /// Palette for coloring blade arcs.
  static let bladePalette: [NSColor] = [
    .systemRed, .systemOrange, .systemYellow, .systemGreen,
    .systemTeal, .systemCyan, .systemBlue, .systemPurple,
    .systemPink, .systemBrown, .systemIndigo, .systemMint,
  ]

  static func bladeNormal(index: Int, bladeCount: Int, tilt: Float, elevation: Float) -> SIMD3<Float> {
    let baseAngle = Float(index) * (2.0 * .pi / Float(max(1, bladeCount)))
    let radial = SIMD3<Float>(cos(baseAngle), 0, sin(baseAngle))
    let tangential = SIMD3<Float>(-sin(baseAngle), 0, cos(baseAngle))
    let up = SIMD3<Float>(0, 1, 0)
    let n = cos(tilt) * radial + sin(tilt) * tangential + tan(elevation) * up
    return simd_normalize(n)
  }

  static func closedThreshold(bladeCount: Int, radius: Float, elevation: Float) -> Float {
    let apex = radius * sin(elevation)
    let equator = radius * cos(elevation) * cos(.pi / Float(max(1, bladeCount)))
    return min(apex, equator)
  }

  /// Full intersection circle points on the sphere surface.
  static func intersectionCircle(
    normal: SIMD3<Float>, threshold: Float, radius: Float, segments: Int = 128
  ) -> [SIMD3<Float>] {
    guard abs(threshold) < radius else { return [] }
    let center = normal * threshold
    let circleR = sqrt(max(0, radius * radius - threshold * threshold))

    let arbitrary: SIMD3<Float> = abs(normal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
    let u = simd_normalize(simd_cross(normal, arbitrary))
    let v = simd_cross(normal, u)

    var points: [SIMD3<Float>] = []
    for i in 0...segments {
      let theta = Float(i) * 2.0 * .pi / Float(segments)
      let pt = center + circleR * (cos(theta) * u + sin(theta) * v)
      if pt.y >= -0.01 {
        let len = simd_length(pt)
        if len > 0.001 {
          points.append(pt * (radius / len))
        }
      }
    }
    return points
  }

  /// Full blade arc: equator entry → (seam point with next blade) → visual endpoint
  /// where previous blade's seam point meets this blade's circle.
  /// One continuous trace along this blade's circle.
  static func seamArc(
    bladeIndex: Int, bladeCount: Int, threshold: Float, radius: Float,
    tilt: Float, elevation: Float, segments: Int = 64
  ) -> [SIMD3<Float>] {
    let n0 = bladeNormal(index: bladeIndex, bladeCount: bladeCount, tilt: tilt, elevation: elevation)
    guard abs(threshold) < radius else { return [] }
    guard abs(threshold) > 0.01 else { return [] }

    let center = n0 * threshold
    let circleR = sqrt(max(0, radius * radius - threshold * threshold))
    let arbitrary: SIMD3<Float> = abs(n0.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
    let u = simd_normalize(simd_cross(n0, arbitrary))
    let v = simd_cross(n0, u)

    func circlePoint(_ theta: Float) -> SIMD3<Float> {
      center + circleR * (cos(theta) * u + sin(theta) * v)
    }

    // Equator entry (Y=0, Y increasing)
    let alpha = circleR * u.y
    let beta = circleR * v.y
    let gamma = -center.y
    let mag = sqrt(alpha * alpha + beta * beta)
    guard mag > 0.0001 else { return [] }
    let ratio = gamma / mag
    guard abs(ratio) <= 1.01 else { return [] }
    let base = atan2(beta, alpha)
    let delta = acos(min(max(ratio, -1), 1))
    let r1 = base + delta
    let r2 = base - delta
    let dY = circleR * (-u.y * sin(r1) + v.y * cos(r1))
    var thetaStart = dY > 0 ? r1 : r2

    // If circle entirely above equator, start from lowest Y
    if circlePoint(thetaStart).y < -0.1 {
      thetaStart = atan2(v.y, u.y) + .pi
    }

    // Visual endpoint: where the PREVIOUS blade's seam point meets this circle.
    // This is where blade (n-1)'s boundary crosses blade n's plane — that point
    // is on blade n's circle, and it's where the aperture edge ends for this blade.
    let prevIndex = (bladeIndex - 1 + bladeCount) % bladeCount
    let nPrev = bladeNormal(index: prevIndex, bladeCount: bladeCount, tilt: tilt, elevation: elevation)
    let alpha2 = circleR * simd_dot(u, nPrev)
    let beta2 = circleR * simd_dot(v, nPrev)
    let gamma2 = threshold * (1.0 - simd_dot(n0, nPrev))
    let mag2 = sqrt(alpha2 * alpha2 + beta2 * beta2)
    guard mag2 > 0.0001 else { return [] }
    let ratio2 = gamma2 / mag2
    guard abs(ratio2) <= 1.01 else { return [] }
    let base2 = atan2(beta2, alpha2)
    let delta2 = acos(min(max(ratio2, -1), 1))
    let sr1 = base2 + delta2
    let sr2 = base2 - delta2
    let thetaEnd = circlePoint(sr1).y >= circlePoint(sr2).y ? sr1 : sr2

    // Pick arc direction (apex on interior)
    var spanPos = thetaEnd - thetaStart
    if spanPos < 0 { spanPos += 2 * .pi }
    let spanNeg = spanPos - 2 * .pi
    let yPos = circlePoint(thetaStart + spanPos * 0.5).y
    let yNeg = circlePoint(thetaStart + spanNeg * 0.5).y
    let span = yPos >= yNeg ? spanPos : spanNeg

    var points: [SIMD3<Float>] = []
    for i in 0...segments {
      let t = Float(i) / Float(segments)
      let theta = thetaStart + t * span
      var pt = circlePoint(theta)
      let len = simd_length(pt)
      if len > 0.001 { pt = pt * (radius / len) }
      guard pt.y >= -0.01 else { continue }
      points.append(pt)
    }
    return points
  }
}

// MARK: - 3D SceneKit View

private struct IrisPlaneScene3DView: NSViewRepresentable {
  let tilt: Float
  let elevation: Float
  let threshold: Float
  let closedThreshold: Float
  let bladeCount: Int
  let domeRadius: Float
  let showAllBlades: Bool
  let showFullCircle: Bool
  let showPlane: Bool
  let showNormals: Bool
  let yawDegrees: Float
  let pitchDegrees: Float
  let cameraDistance: Float

  private static let lookAtTarget = SIMD3<Float>(0, 0.3, 0)

  func makeNSView(context: Context) -> SCNView {
    let scnView = SCNView()
    scnView.scene = SCNScene()
    scnView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
    scnView.allowsCameraControl = false
    scnView.autoenablesDefaultLighting = true

    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.name = "camera"
    updateCamera(cameraNode)
    scnView.scene?.rootNode.addChildNode(cameraNode)

    let domeNode = SCNNode(geometry: makeHemisphereWireframe(radius: domeRadius))
    domeNode.name = "dome"
    scnView.scene?.rootNode.addChildNode(domeNode)

    let axisNode = SCNNode(geometry: makeAxisLine(length: domeRadius * 1.3))
    axisNode.name = "axis"
    scnView.scene?.rootNode.addChildNode(axisNode)

    let contentNode = SCNNode()
    contentNode.name = "content"
    scnView.scene?.rootNode.addChildNode(contentNode)

    return scnView
  }

  func updateNSView(_ scnView: SCNView, context: Context) {
    guard let scene = scnView.scene,
          let contentNode = scene.rootNode.childNode(withName: "content", recursively: false) else { return }

    if let cam = scene.rootNode.childNode(withName: "camera", recursively: false) {
      updateCamera(cam)
    }

    contentNode.childNodes.forEach { $0.removeFromParentNode() }

    let n0 = IrisPlaneAlgorithm.bladeNormal(
      index: 0, bladeCount: bladeCount, tilt: tilt, elevation: elevation
    )

    // Cutting plane (blade 0 only)
    if showPlane {
      contentNode.addChildNode(makePlaneNode(normal: n0, threshold: threshold, size: domeRadius * 2.5))
    }

    // Closed-threshold reference ring (dim green)
    if abs(closedThreshold) < domeRadius {
      let closedPts = IrisPlaneAlgorithm.intersectionCircle(
        normal: n0, threshold: closedThreshold, radius: domeRadius, segments: 96
      )
      if closedPts.count > 2 {
        contentNode.addChildNode(makeLineStrip(
          points: closedPts, color: NSColor.systemGreen.withAlphaComponent(0.25), lineWidth: 1
        ))
      }
    }

    // Full intersection circle (blade 0, cyan)
    if showFullCircle {
      let circlePts = IrisPlaneAlgorithm.intersectionCircle(
        normal: n0, threshold: threshold, radius: domeRadius, segments: 128
      )
      if circlePts.count > 2 {
        contentNode.addChildNode(makeLineStrip(
          points: circlePts, color: NSColor.cyan.withAlphaComponent(0.4), lineWidth: 1
        ))
      }
    }

    // Blade arcs
    let bladeRange = showAllBlades ? 0..<bladeCount : 0..<1
    let palette = IrisPlaneAlgorithm.bladePalette

    for i in bladeRange {
      let color = palette[i % palette.count]
      let seamPts = IrisPlaneAlgorithm.seamArc(
        bladeIndex: i, bladeCount: bladeCount, threshold: threshold, radius: domeRadius,
        tilt: tilt, elevation: elevation
      )
      if seamPts.count > 1 {
        contentNode.addChildNode(makeLineStrip(
          points: seamPts, color: color, lineWidth: showAllBlades ? 2 : 3
        ))
      }

      // Blade normal
      if showNormals {
        let ni = IrisPlaneAlgorithm.bladeNormal(
          index: i, bladeCount: bladeCount, tilt: tilt, elevation: elevation
        )
        let arrowLen: Float = showAllBlades ? domeRadius * 0.7 : domeRadius * 1.4
        let alpha: CGFloat = showAllBlades ? 0.4 : 1.0
        contentNode.addChildNode(makeArrow(
          from: .zero, to: ni * arrowLen,
          color: color.withAlphaComponent(alpha), thickness: 0.004
        ))
        let tipSphere = SCNSphere(radius: showAllBlades ? 0.015 : 0.03)
        tipSphere.firstMaterial?.diffuse.contents = color.withAlphaComponent(alpha)
        tipSphere.firstMaterial?.lightingModel = .constant
        let tipNode = SCNNode(geometry: tipSphere)
        tipNode.simdPosition = ni * arrowLen
        contentNode.addChildNode(tipNode)
      }
    }

    // Plane center indicator (purple dot)
    let planeCenterPos = n0 * threshold
    if simd_length(planeCenterPos) > 0.01 {
      let pcSphere = SCNSphere(radius: 0.015)
      pcSphere.firstMaterial?.diffuse.contents = NSColor.systemPurple
      pcSphere.firstMaterial?.lightingModel = .constant
      let pcNode = SCNNode(geometry: pcSphere)
      pcNode.simdPosition = planeCenterPos
      contentNode.addChildNode(pcNode)
      contentNode.addChildNode(makeArrow(
        from: .zero, to: planeCenterPos,
        color: NSColor.systemPurple.withAlphaComponent(0.3), thickness: 0.002
      ))
    }

    // Equator ring
    contentNode.addChildNode(makeEquatorRing(radius: domeRadius))
  }

  // MARK: - Camera

  private func updateCamera(_ node: SCNNode) {
    let pos = PlaygroundCamera.position(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
    let target = Self.lookAtTarget
    node.simdPosition = pos + target
    node.simdLook(at: target, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
  }

  // MARK: - Geometry Helpers

  private func makeHemisphereWireframe(radius: Float) -> SCNGeometry {
    let latSegs = 16
    let lonSegs = 32
    var positions: [SCNVector3] = []
    positions.append(SCNVector3(0, radius, 0))
    for lat in 1...latSegs {
      let theta = Float(lat) * (.pi / 2) / Float(latSegs)
      let y = radius * cos(theta)
      let r = radius * sin(theta)
      for lon in 0..<lonSegs {
        let phi = Float(lon) * 2 * .pi / Float(lonSegs)
        positions.append(SCNVector3(r * cos(phi), y, r * sin(phi)))
      }
    }
    var indices: [Int32] = []
    for lon in 0..<lonSegs {
      indices.append(0)
      indices.append(Int32(1 + lon))
      indices.append(Int32(1 + (lon + 1) % lonSegs))
    }
    for lat in 1..<latSegs {
      let ring = 1 + (lat - 1) * lonSegs
      let next = 1 + lat * lonSegs
      for lon in 0..<lonSegs {
        let nl = (lon + 1) % lonSegs
        indices.append(contentsOf: [Int32(ring + lon), Int32(next + lon), Int32(ring + nl)])
        indices.append(contentsOf: [Int32(ring + nl), Int32(next + lon), Int32(next + nl)])
      }
    }
    let source = SCNGeometrySource(vertices: positions)
    let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
    let element = SCNGeometryElement(data: data, primitiveType: .triangles,
                                     primitiveCount: indices.count / 3, bytesPerIndex: 4)
    let geo = SCNGeometry(sources: [source], elements: [element])
    let mat = SCNMaterial()
    mat.fillMode = .lines
    mat.diffuse.contents = NSColor.gray.withAlphaComponent(0.15)
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    geo.materials = [mat]
    return geo
  }

  private func makeAxisLine(length: Float) -> SCNGeometry {
    let verts = [SCNVector3(0, 0, 0), SCNVector3(0, length, 0)]
    let indices: [Int32] = [0, 1]
    let source = SCNGeometrySource(vertices: verts)
    let data = Data(bytes: indices, count: indices.count * 4)
    let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 4)
    let geo = SCNGeometry(sources: [source], elements: [element])
    let mat = SCNMaterial()
    mat.diffuse.contents = NSColor.white.withAlphaComponent(0.3)
    mat.lightingModel = .constant
    geo.materials = [mat]
    return geo
  }

  private func makeEquatorRing(radius: Float) -> SCNNode {
    let segments = 64
    var verts: [SCNVector3] = []
    var indices: [Int32] = []
    for i in 0...segments {
      let theta = Float(i) * 2 * .pi / Float(segments)
      verts.append(SCNVector3(radius * cos(theta), 0, radius * sin(theta)))
      if i > 0 {
        indices.append(Int32(i - 1))
        indices.append(Int32(i))
      }
    }
    let source = SCNGeometrySource(vertices: verts)
    let data = Data(bytes: indices, count: indices.count * 4)
    let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: 4)
    let geo = SCNGeometry(sources: [source], elements: [element])
    let mat = SCNMaterial()
    mat.diffuse.contents = NSColor.gray.withAlphaComponent(0.3)
    mat.lightingModel = .constant
    geo.materials = [mat]
    return SCNNode(geometry: geo)
  }

  private func makePlaneNode(normal: SIMD3<Float>, threshold: Float, size: Float) -> SCNNode {
    let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
    let mat = SCNMaterial()
    mat.diffuse.contents = NSColor.systemBlue.withAlphaComponent(0.15)
    mat.lightingModel = .constant
    mat.isDoubleSided = true
    plane.materials = [mat]

    let node = SCNNode(geometry: plane)
    node.simdPosition = normal * threshold

    let defaultNormal = SIMD3<Float>(0, 0, 1)
    let dot = simd_dot(defaultNormal, normal)
    if dot < -0.999 {
      node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    } else if dot < 0.999 {
      let axis = simd_normalize(simd_cross(defaultNormal, normal))
      let angle = acos(min(max(dot, -1), 1))
      node.simdOrientation = simd_quatf(angle: angle, axis: axis)
    }

    return node
  }

  private func makeArrow(from: SIMD3<Float>, to: SIMD3<Float>, color: NSColor, thickness: Float) -> SCNNode {
    let verts = [SCNVector3(from.x, from.y, from.z), SCNVector3(to.x, to.y, to.z)]
    let indices: [Int32] = [0, 1]
    let source = SCNGeometrySource(vertices: verts)
    let data = Data(bytes: indices, count: indices.count * 4)
    let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: 1, bytesPerIndex: 4)
    let geo = SCNGeometry(sources: [source], elements: [element])
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.lightingModel = .constant
    geo.materials = [mat]
    return SCNNode(geometry: geo)
  }

  private func makeLineStrip(points: [SIMD3<Float>], color: NSColor, lineWidth: CGFloat) -> SCNNode {
    let verts: [SCNVector3] = points.map { SCNVector3($0.x, $0.y, $0.z) }
    var indices: [Int32] = []
    for i in 1..<verts.count {
      indices.append(Int32(i - 1))
      indices.append(Int32(i))
    }
    let source = SCNGeometrySource(vertices: verts)
    let data = Data(bytes: indices, count: indices.count * 4)
    let element = SCNGeometryElement(data: data, primitiveType: .line, primitiveCount: indices.count / 2, bytesPerIndex: 4)
    let geo = SCNGeometry(sources: [source], elements: [element])
    let mat = SCNMaterial()
    mat.diffuse.contents = color
    mat.lightingModel = .constant
    geo.materials = [mat]

    let node = SCNNode(geometry: geo)

    if lineWidth > 1 {
      let step = max(1, points.count / 40)
      for i in stride(from: 0, to: points.count, by: step) {
        let bead = SCNSphere(radius: CGFloat(0.006 * lineWidth))
        bead.firstMaterial?.diffuse.contents = color
        bead.firstMaterial?.lightingModel = .constant
        let beadNode = SCNNode(geometry: bead)
        beadNode.simdPosition = points[i]
        node.addChildNode(beadNode)
      }
    }
    return node
  }
}

// MARK: - Preview

#Preview("Iris Plane Debug") {
  IrisPlaneDebugView()
    .frame(width: 1000, height: 650)
}
