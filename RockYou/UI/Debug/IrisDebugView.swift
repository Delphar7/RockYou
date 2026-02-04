// IrisDebugView.swift
// RockYou/UI/Debug
//
// Debug view for the iris model — each blade is defined by a tilted
// plane rather than a sphere. Visualizes boundary circles, seam points, and
// blade ownership on the dome surface. The `tilt` parameter controls the spiral.

import simd
import SwiftUI
import SceneKit
import os

private let log = Logger(subsystem: "com.rockyou", category: "IrisDebug")

// MARK: - Metal Compute Bridge

/// Params struct matching IrisComputeParams in IrisCompute.metal.
/// All fields are 4-byte aligned — 32 bytes total, no padding surprises.
private struct IrisComputeParams {
  var bladeCount: Int32
  var domeRadius: Float
  var aperture: Float
  var tilt: Float
  var elevation: Float
  var arcPointCount: Int32
  var latSteps: Int32
  var lonSteps: Int32
}

/// Results from the two Metal compute kernels.
private struct IrisMetalResult: Sendable {
  let seamArcs: [[SIMD3<Float>]]   // [bladeCount][arcPointCount after filtering]
  let ownership: [Int32]            // [latSteps * lonSteps]
  let latSteps: Int
  let lonSteps: Int
}

// MARK: - Iris Algorithm

struct IrisAlgorithm {
  let bladeCount: Int
  let domeRadius: Float
  let tilt: Float       // 0 = radial (no spiral), π/2 = full tangential
  let elevation: Float  // Lifts normal toward dome apex

  /// Blade normal for the given index.
  /// Construction: cos(tilt)*radial + sin(tilt)*tangential + tan(elevation)*up, normalized.
  func bladeNormal(index: Int) -> SIMD3<Float> {
    let baseAngle = Float(index) * (2.0 * .pi / Float(max(1, bladeCount)))
    let radial = SIMD3<Float>(cos(baseAngle), 0, sin(baseAngle))
    let tangential = SIMD3<Float>(-sin(baseAngle), 0, cos(baseAngle))
    let up = SIMD3<Float>(0, 1, 0)
    let n = cos(tilt) * radial + sin(tilt) * tangential + tan(elevation) * up
    return simd_normalize(n)
  }

  /// True when blade `index` covers point Q: dot(Q, n_i) > d.
  func bladeCoverage(Q: SIMD3<Float>, index: Int, aperture: Float) -> Bool {
    simd_dot(Q, bladeNormal(index: index)) > aperture
  }

  /// Pinwheel rule: blade i visible when dot(Q, n_i) > d AND dot(Q, n_{i+1}) <= d.
  func findVisibleBlade(Q: SIMD3<Float>, aperture: Float) -> Int? {
    for i in 0..<bladeCount {
      let next = (i + 1) % bladeCount
      if simd_dot(Q, bladeNormal(index: i)) > aperture
          && simd_dot(Q, bladeNormal(index: next)) <= aperture {
        return i
      }
    }
    return nil
  }

  /// Boundary circle: intersection of plane dot(Q, n_i) = d with sphere |Q| = R.
  func boundaryCircle(index: Int, aperture: Float) -> (center: SIMD3<Float>, radius: Float, normal: SIMD3<Float>)? {
    let R = domeRadius
    let d = aperture
    guard abs(d) < R else { return nil }
    let n = bladeNormal(index: index)
    return (center: n * d, radius: sqrt(R * R - d * d), normal: n)
  }

  /// Seam point: intersection of two adjacent boundary planes with the dome sphere.
  /// Uses predecessor (i-1) to match the production seam arc endpoint.
  /// Returns the upper-hemisphere point, or nil if none exists.
  func seamPoint(bladeIndex: Int, aperture: Float) -> SIMD3<Float>? {
    let R = domeRadius
    let d = aperture
    let ni = bladeNormal(index: bladeIndex)
    let nj = bladeNormal(index: (bladeIndex - 1 + bladeCount) % bladeCount)

    let c = simd_dot(ni, nj)
    guard abs(1 + c) > 0.0001 else { return nil }

    // Point on the intersection line: P = d/(1+c) * (n_i + n_j)
    let P = (d / (1.0 + c)) * (ni + nj)

    // Line direction
    let cross = simd_cross(ni, nj)
    let crossLen = simd_length(cross)
    guard crossLen > 0.0001 else { return nil }
    let L = cross / crossLen

    // Intersect P + tL with sphere |Q| = R
    let PdotL = simd_dot(P, L)
    let PdotP = simd_dot(P, P)
    let disc = PdotL * PdotL - PdotP + R * R
    guard disc >= 0 else { return nil }

    let sqrtDisc = sqrt(disc)
    let Q1 = P + (-PdotL + sqrtDisc) * L
    let Q2 = P + (-PdotL - sqrtDisc) * L

    // Pick upper-hemisphere point(s)
    switch (Q1.y >= 0, Q2.y >= 0) {
    case (true, true):  return Q1.y >= Q2.y ? Q1 : Q2
    case (true, false): return Q1
    case (false, true): return Q2
    case (false, false): return nil
    }
  }

  // MARK: - Analytical seam arc (matches Metal IrisAlgorithm.h)

  struct SeamCircle {
    let center: SIMD3<Float>
    let circleRadius: Float
    let normal: SIMD3<Float>
    let u: SIMD3<Float>
    let v: SIMD3<Float>
  }

  func computeSeamCircle(index: Int, aperture: Float) -> SeamCircle? {
    let R = domeRadius
    guard abs(aperture) < R else { return nil }
    let n = bladeNormal(index: index)
    let arbitrary: SIMD3<Float> = abs(n.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
    let u = simd_normalize(simd_cross(n, arbitrary))
    let v = simd_cross(n, u)
    return SeamCircle(
      center: n * aperture,
      circleRadius: sqrt(max(0, R * R - aperture * aperture)),
      normal: n, u: u, v: v
    )
  }

  func seamCirclePoint(_ sc: SeamCircle, theta: Float) -> SIMD3<Float> {
    sc.center + sc.circleRadius * (cos(theta) * sc.u + sin(theta) * sc.v)
  }

  /// Solve α·cos(θ) + β·sin(θ) = γ. Returns two roots or nil.
  private func solveTrigEquation(alpha: Float, beta: Float, gamma: Float) -> (Float, Float)? {
    let mag = sqrt(alpha * alpha + beta * beta)
    guard mag > 0.0001 else { return nil }
    let ratio = gamma / mag
    guard abs(ratio) <= 1.01 else { return nil }
    let base = atan2(beta, alpha)
    let delta = acos(min(max(ratio, -1), 1))
    return (base + delta, base - delta)
  }

  /// Equator crossing where Y is increasing (entering upper hemisphere).
  func findEquatorEntry(_ sc: SeamCircle) -> Float? {
    let alpha = sc.circleRadius * sc.u.y
    let beta  = sc.circleRadius * sc.v.y
    let gamma = -sc.center.y
    guard let (r1, r2) = solveTrigEquation(alpha: alpha, beta: beta, gamma: gamma) else { return nil }
    let dY = sc.circleRadius * (-sc.u.y * sin(r1) + sc.v.y * cos(r1))
    return dY > 0 ? r1 : r2
  }

  /// Seam point theta: where blade i's boundary circle meets another blade's plane.
  /// Picks the root in the upper hemisphere (higher Y).
  func findSeamPointTheta(_ sc: SeamCircle, nextNormal: SIMD3<Float>, threshold: Float) -> Float? {
    let alpha = sc.circleRadius * simd_dot(sc.u, nextNormal)
    let beta  = sc.circleRadius * simd_dot(sc.v, nextNormal)
    let gamma = threshold * (1.0 - simd_dot(sc.normal, nextNormal))
    guard let (r1, r2) = solveTrigEquation(alpha: alpha, beta: beta, gamma: gamma) else { return nil }
    let p1 = seamCirclePoint(sc, theta: r1)
    let p2 = seamCirclePoint(sc, theta: r2)
    return p1.y >= p2.y ? r1 : r2
  }

  /// Analytical seam arc from equator entry to seam point.
  /// Arc direction chosen so the Y axis (apex) is on the interior — matches Metal shader.
  func seamArcPoints(index: Int, aperture: Float, segments: Int = 64) -> [SIMD3<Float>] {
    guard let sc = computeSeamCircle(index: index, aperture: aperture) else { return [] }

    var thetaStart: Float
    if let entry = findEquatorEntry(sc) {
      thetaStart = entry
    } else {
      // Circle entirely above equator — start from lowest Y point
      thetaStart = atan2(sc.v.y, sc.u.y) + .pi
    }

    let predecessor = (index - 1 + bladeCount) % bladeCount
    let nPrev = bladeNormal(index: predecessor)
    guard let thetaEnd = findSeamPointTheta(sc, nextNormal: nPrev, threshold: aperture) else { return [] }

    // Pick the arc whose midpoint has higher Y (apex on interior)
    var spanPos = thetaEnd - thetaStart
    if spanPos < 0 { spanPos += 2 * .pi }
    let spanNeg = spanPos - 2 * .pi

    let yPos = seamCirclePoint(sc, theta: thetaStart + spanPos * 0.5).y
    let yNeg = seamCirclePoint(sc, theta: thetaStart + spanNeg * 0.5).y
    let span = yPos >= yNeg ? spanPos : spanNeg

    var points: [SIMD3<Float>] = []
    for i in 0...segments {
      let t = Float(i) / Float(segments)
      let theta = thetaStart + t * span
      var pt = seamCirclePoint(sc, theta: theta)
      let len = simd_length(pt)
      if len > 0.001 { pt = pt * (domeRadius / len) }
      points.append(pt)
    }
    return points
  }
}

// MARK: - Color Helpers

private func bladeColor(_ index: Int, count: Int, alpha: Double = 1.0) -> Color {
  Color(hue: Double(index) / Double(max(1, count)), saturation: 0.8, brightness: 0.9, opacity: alpha)
}

private func bladeNSColor(_ index: Int, count: Int, alpha: CGFloat = 1.0) -> NSColor {
  NSColor(hue: CGFloat(index) / CGFloat(max(1, count)), saturation: 0.8, brightness: 0.9, alpha: alpha)
}

// MARK: - Debug View

struct IrisDebugView: View {
  @State private var aperture: Double = 0.3
  @State private var tilt: Double = 0.0
  @State private var elevation: Double = 0.0
  @State private var bladeCount: Int = 6
  @State private var bladeIndex: Int = 0
  @State private var showAllBlades: Bool = true
  @State private var showSamples: Bool = true

  // Camera orbit (matches RealityDebugView)
  @State private var yawDegrees: Double = 45
  @State private var pitchDegrees: Double = 35
  @State private var cameraDistance: Double = 2.5

  private let domeRadius: Float = 1.0

  private var algo: IrisAlgorithm {
    IrisAlgorithm(
      bladeCount: bladeCount,
      domeRadius: domeRadius,
      tilt: Float(tilt),
      elevation: Float(elevation)
    )
  }

  /// Dispatch both Metal compute kernels and return results, or nil to fall back to Swift.
  private func metalResults(aperture: Float) -> IrisMetalResult? {
    let metal = MetalCompute.shared
    guard metal.isAvailable else { return nil }

    let latSteps = 16
    let lonSteps = 32
    let arcPointCount = 65

    let params = IrisComputeParams(
      bladeCount: Int32(bladeCount),
      domeRadius: domeRadius,
      aperture: aperture,
      tilt: Float(tilt),
      elevation: Float(elevation),
      arcPointCount: Int32(arcPointCount),
      latSteps: Int32(latSteps),
      lonSteps: Int32(lonSteps)
    )

    let seamCount = bladeCount * arcPointCount
    guard let seamFlat: [SIMD3<Float>] = metal.execute(
      "irisComputeSeamArcs", params: params, count: seamCount
    ) else { return nil }

    let ownershipCount = latSteps * lonSteps
    guard let ownership: [Int32] = metal.execute(
      "irisComputeBladeOwnership", params: params, count: ownershipCount
    ) else { return nil }

    // Split flat seam array into per-blade arrays, filtering invalid points
    var seamArcs: [[SIMD3<Float>]] = []
    for blade in 0..<bladeCount {
      let start = blade * arcPointCount
      let end = start + arcPointCount
      let bladePoints = Array(seamFlat[start..<end]).filter { $0.y > -999 }
      seamArcs.append(bladePoints)
    }

    return IrisMetalResult(
      seamArcs: seamArcs, ownership: ownership,
      latSteps: latSteps, lonSteps: lonSteps
    )
  }

  var body: some View {
    let metalResult = metalResults(aperture: Float(aperture))

    HSplitView {
      // Left: 2D top-down Canvas (XZ projection, looking down Y axis)
      canvas2D(metalResult: metalResult)
        .background(Color.black)
        .frame(minWidth: 300, minHeight: 300)

      // Middle: 3D SceneKit view with camera overlay
      IrisScene3DView(
        bladeIndex: bladeIndex,
        bladeCount: bladeCount,
        aperture: Float(aperture),
        tilt: Float(tilt),
        elevation: Float(elevation),
        domeRadius: domeRadius,
        showAllBlades: showAllBlades,
        showSamples: showSamples,
        yawDegrees: Float(yawDegrees),
        pitchDegrees: Float(pitchDegrees),
        cameraDistance: Float(cameraDistance),
        seamArcs: metalResult?.seamArcs,
        ownership: metalResult?.ownership,
        ownershipLatSteps: metalResult?.latSteps ?? 12,
        ownershipLonSteps: metalResult?.lonSteps ?? 24
      )
      .overlay {
        CameraEventCapture(
          distance: $cameraDistance,
          yawDegrees: $yawDegrees,
          pitchDegrees: $pitchDegrees,
          distanceRange: 0.5...5.0
        )
      }
      .frame(minWidth: 300, minHeight: 300)

      // Right: Controls
      controlsPanel
        .frame(width: 280)
    }
    .onChange(of: bladeCount) { _, newCount in
      if bladeIndex >= newCount { bladeIndex = newCount - 1 }
    }
  }

  // MARK: - 2D Canvas (XZ top-down projection)

  private func canvas2D(metalResult: IrisMetalResult?) -> some View {
    GeometryReader { geo in
      Canvas { ctx, size in
        let scale = min(size.width, size.height) * 0.4
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let algo = self.algo
        let ap = Float(aperture)

        // XZ → screen (Z positive = screen up)
        func toScreen(_ p: SIMD3<Float>) -> CGPoint {
          CGPoint(
            x: center.x + CGFloat(p.x) * scale,
            y: center.y - CGFloat(p.z) * scale
          )
        }

        func toScreen2D(_ x: Float, _ z: Float) -> CGPoint {
          CGPoint(
            x: center.x + CGFloat(x) * scale,
            y: center.y - CGFloat(z) * scale
          )
        }

        // Dome boundary circle (equator in XZ)
        let domeCircle = Path(ellipseIn: CGRect(
          x: center.x - scale, y: center.y - scale,
          width: scale * 2, height: scale * 2
        ))
        ctx.stroke(domeCircle, with: .color(.gray.opacity(0.5)), lineWidth: 2)

        // Origin marker
        ctx.fill(Path(ellipseIn: CGRect(
          x: center.x - 4, y: center.y - 4, width: 8, height: 8
        )), with: .color(.white))

        // Sample points colored by blade ownership
        if showSamples {
          let R = domeRadius
          let sLatSteps = metalResult?.latSteps ?? 16
          let sLonSteps = metalResult?.lonSteps ?? 32
          for lat in 0..<sLatSteps {
            let theta = Float(lat) * (Float.pi / 2.0) / Float(sLatSteps)
            for lon in 0..<sLonSteps {
              let phi = Float(lon) * 2.0 * Float.pi / Float(sLonSteps)
              let Q = R * SIMD3<Float>(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
              let blade: Int?
              if let own = metalResult?.ownership {
                let oi = lat * sLonSteps + lon
                blade = own[oi] >= 0 ? Int(own[oi]) : nil
              } else {
                blade = algo.findVisibleBlade(Q: Q, aperture: ap)
              }
              let screenPt = toScreen(Q)
              let dotSize: CGFloat = 3
              if let b = blade {
                ctx.fill(Path(ellipseIn: CGRect(
                  x: screenPt.x - dotSize / 2, y: screenPt.y - dotSize / 2,
                  width: dotSize, height: dotSize
                )), with: .color(bladeColor(b, count: algo.bladeCount, alpha: 0.6)))
              } else {
                ctx.fill(Path(ellipseIn: CGRect(
                  x: screenPt.x - dotSize / 2, y: screenPt.y - dotSize / 2,
                  width: dotSize, height: dotSize
                )), with: .color(.gray.opacity(0.2)))
              }
            }
          }
        }

        // Per-blade: normals, boundary circles, seam points
        let indicesToDraw = showAllBlades ? Array(0..<algo.bladeCount) : [bladeIndex]

        for idx in indicesToDraw {
          let isSelected = idx == bladeIndex
          let color = bladeColor(idx, count: algo.bladeCount)

          // Blade normal as arrow from origin
          let n = algo.bladeNormal(index: idx)
          let arrowEnd = toScreen2D(n.x * 0.3, n.z * 0.3)
          var arrowPath = Path()
          arrowPath.move(to: center)
          arrowPath.addLine(to: arrowEnd)
          ctx.stroke(arrowPath, with: .color(color), lineWidth: isSelected ? 3.0 : 1.5)

          // Dot at arrow tip
          let tipSize: CGFloat = isSelected ? 10 : 8
          ctx.fill(Path(ellipseIn: CGRect(
            x: arrowEnd.x - tipSize / 2, y: arrowEnd.y - tipSize / 2, width: tipSize, height: tipSize
          )), with: .color(color))

          // Seam arc: Metal compute or Swift fallback
          let seamArc: [SIMD3<Float>]
          if let metalArcs = metalResult?.seamArcs, idx < metalArcs.count {
            seamArc = metalArcs[idx]
          } else {
            seamArc = algo.seamArcPoints(index: idx, aperture: ap)
          }
          if seamArc.count > 1 {
            var arcPath = Path()
            arcPath.move(to: toScreen(seamArc[0]))
            for pt in seamArc.dropFirst() {
              arcPath.addLine(to: toScreen(pt))
            }
            ctx.stroke(arcPath, with: .color(color), lineWidth: isSelected ? 3.0 : 1.0)
          }

          // Seam point
          if let sp = algo.seamPoint(bladeIndex: idx, aperture: ap) {
            let spScreen = toScreen(sp)
            ctx.fill(Path(ellipseIn: CGRect(
              x: spScreen.x - 5, y: spScreen.y - 5, width: 10, height: 10
            )), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(
              x: spScreen.x - 5, y: spScreen.y - 5, width: 10, height: 10
            )), with: .color(color), lineWidth: 2)
          }
        }

        // Legend
        let legendY: CGFloat = 20
        ctx.draw(Text("-> Blade normals").foregroundColor(.white).font(.caption),
                 at: CGPoint(x: 80, y: legendY))
        ctx.draw(Text("-- Boundary circles").foregroundColor(.cyan).font(.caption),
                 at: CGPoint(x: 80, y: legendY + 16))
        ctx.draw(Text("o  Seam points").foregroundColor(.white).font(.caption),
                 at: CGPoint(x: 80, y: legendY + 32))
        if showSamples {
          ctx.draw(Text(".  Blade ownership").foregroundColor(.gray).font(.caption),
                   at: CGPoint(x: 80, y: legendY + 48))
        }
      }
    }
  }

  // MARK: - Controls Panel

  private var controlsPanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox("Aperture") {
          VStack(alignment: .leading) {
            Slider(value: $aperture, in: -0.5...0.95)
            Text("d = \(aperture, specifier: "%.3f")")
              .font(.caption)
            Text("Higher = less coverage (more open)")
              .font(.caption2).foregroundStyle(.secondary)
          }
        }

        GroupBox("Spiral") {
          VStack(alignment: .leading) {
            HStack {
              Text("Tilt:")
              Slider(value: $tilt, in: 0...(Double.pi / 2))
              Text("\(tilt * 180 / .pi, specifier: "%.1f")\u{00B0}")
                .frame(width: 44, alignment: .trailing)
            }
            Text("0 = radial, 90 = full tangential")
              .font(.caption2).foregroundStyle(.secondary)

            HStack {
              Text("Elev:")
              Slider(value: $elevation, in: 0...(Double.pi / 4))
              Text("\(elevation * 180 / .pi, specifier: "%.1f")\u{00B0}")
                .frame(width: 44, alignment: .trailing)
            }
            Text("Lifts blade normal toward apex")
              .font(.caption2).foregroundStyle(.secondary)
          }
          .font(.caption)
        }

        GroupBox("Blade") {
          VStack(alignment: .leading) {
            Stepper("Blade: \(bladeIndex)", value: $bladeIndex, in: 0...(bladeCount - 1))
            Stepper("Count: \(bladeCount)", value: $bladeCount, in: 3...12)
            Toggle("Show all blades", isOn: $showAllBlades)
            Toggle("Show samples", isOn: $showSamples)
          }
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
    let algo = self.algo
    let ap = Float(aperture)
    let n = algo.bladeNormal(index: bladeIndex)

    return VStack(alignment: .leading, spacing: 4) {
      Text("Normal \(bladeIndex):")
        .font(.caption.bold())
      Text("  (\(n.x, specifier: "%.3f"), \(n.y, specifier: "%.3f"), \(n.z, specifier: "%.3f"))")

      if let circle = algo.boundaryCircle(index: bladeIndex, aperture: ap) {
        Divider()
        Text("Boundary circle:")
          .font(.caption.bold())
        Text("  Center: (\(circle.center.x, specifier: "%.3f"), \(circle.center.y, specifier: "%.3f"), \(circle.center.z, specifier: "%.3f"))")
        Text("  Radius: \(circle.radius, specifier: "%.3f")")
      }

      if let sp = algo.seamPoint(bladeIndex: bladeIndex, aperture: ap) {
        Divider()
        Text("Seam point:")
          .font(.caption.bold())
        Text("  (\(sp.x, specifier: "%.3f"), \(sp.y, specifier: "%.3f"), \(sp.z, specifier: "%.3f"))")
        Text("  |Q| = \(simd_length(sp), specifier: "%.4f")")
      } else {
        Divider()
        Text("No seam point")
          .foregroundColor(.orange)
      }

      // Apex coverage
      let apex = SIMD3<Float>(0, domeRadius, 0)
      let apexCoverage = (0..<algo.bladeCount).filter {
        algo.bladeCoverage(Q: apex, index: $0, aperture: ap)
      }.count

      Divider()
      Text("Apex coverage: \(apexCoverage)/\(algo.bladeCount)")
      if let v = algo.findVisibleBlade(Q: apex, aperture: ap) {
        Text("Visible at apex: blade \(v)")
      } else {
        Text("No visible blade at apex")
          .foregroundColor(.orange)
      }
    }
    .font(.system(.caption, design: .monospaced))
  }
}

// MARK: - Hemisphere Wireframe

private func makeHemisphereGeometry(radius: Float, latSegments: Int = 12, lonSegments: Int = 24) -> SCNGeometry {
  var positions: [SCNVector3] = []

  // Apex
  positions.append(SCNVector3(0, radius, 0))

  // Latitude rings (top to equator)
  for lat in 1...latSegments {
    let theta = Float(lat) * (Float.pi / 2) / Float(latSegments)
    let y = radius * cos(theta)
    let r = radius * sin(theta)
    for lon in 0..<lonSegments {
      let phi = Float(lon) * 2 * Float.pi / Float(lonSegments)
      positions.append(SCNVector3(r * cos(phi), y, r * sin(phi)))
    }
  }

  var indices: [Int32] = []

  // Apex fan
  for lon in 0..<lonSegments {
    indices.append(0)
    indices.append(Int32(1 + lon))
    indices.append(Int32(1 + (lon + 1) % lonSegments))
  }

  // Latitude bands
  for lat in 1..<latSegments {
    let ringStart = 1 + (lat - 1) * lonSegments
    let nextRingStart = 1 + lat * lonSegments
    for lon in 0..<lonSegments {
      let nextLon = (lon + 1) % lonSegments
      let tl = Int32(ringStart + lon)
      let tr = Int32(ringStart + nextLon)
      let bl = Int32(nextRingStart + lon)
      let br = Int32(nextRingStart + nextLon)
      indices.append(contentsOf: [tl, bl, tr])
      indices.append(contentsOf: [tr, bl, br])
    }
  }

  let source = SCNGeometrySource(vertices: positions)
  let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
  let element = SCNGeometryElement(
    data: indexData,
    primitiveType: .triangles,
    primitiveCount: indices.count / 3,
    bytesPerIndex: MemoryLayout<Int32>.size
  )

  let geo = SCNGeometry(sources: [source], elements: [element])
  let mat = SCNMaterial()
  mat.fillMode = .lines
  mat.diffuse.contents = NSColor.gray.withAlphaComponent(0.2)
  mat.lightingModel = .constant
  mat.isDoubleSided = true
  geo.materials = [mat]
  return geo
}

// MARK: - 3D SceneKit View

struct IrisScene3DView: NSViewRepresentable {
  let bladeIndex: Int
  let bladeCount: Int
  let aperture: Float
  let tilt: Float
  let elevation: Float
  let domeRadius: Float
  let showAllBlades: Bool
  let showSamples: Bool
  let yawDegrees: Float
  let pitchDegrees: Float
  let cameraDistance: Float
  var seamArcs: [[SIMD3<Float>]]? = nil
  var ownership: [Int32]? = nil
  var ownershipLatSteps: Int = 12
  var ownershipLonSteps: Int = 24

  private static let lookAtTarget = SIMD3<Float>(0, 0.3, 0)

  func makeNSView(context: Context) -> SCNView {
    let scnView = SCNView()
    scnView.scene = SCNScene()
    scnView.backgroundColor = .black
    scnView.allowsCameraControl = false
    scnView.autoenablesDefaultLighting = true

    // Camera
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.name = "camera"
    Self.updateCamera(cameraNode, yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
    scnView.scene?.rootNode.addChildNode(cameraNode)

    // Wireframe dome hemisphere
    let domeNode = SCNNode(geometry: makeHemisphereGeometry(radius: domeRadius))
    domeNode.name = "dome"
    scnView.scene?.rootNode.addChildNode(domeNode)

    // Content node (rebuilt on update)
    let contentNode = SCNNode()
    contentNode.name = "content"
    scnView.scene?.rootNode.addChildNode(contentNode)

    return scnView
  }

  private static func updateCamera(_ cameraNode: SCNNode, yaw: Float, pitch: Float, distance: Float) {
    let pos = PlaygroundCamera.position(yaw: yaw, pitch: pitch, distance: distance)
    let target = lookAtTarget
    cameraNode.simdPosition = pos + target
    cameraNode.simdLook(at: target, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
  }

  private static func cameraWorldPosition(yaw: Float, pitch: Float, distance: Float) -> SIMD3<Float> {
    PlaygroundCamera.position(yaw: yaw, pitch: pitch, distance: distance) + lookAtTarget
  }

  /// Opacity based on distance from camera: 1.0 at nearest, fading to minOpacity at farthest.
  private static func depthOpacity(
    position: SIMD3<Float>,
    cameraPos: SIMD3<Float>,
    near: Float,
    far: Float
  ) -> CGFloat {
    let dist = simd_distance(position, cameraPos)
    let t = min(max((dist - near) / max(0.001, far - near), 0), 1)
    return CGFloat(1.0 - t * 0.85) // 1.0 at near, 0.15 at far
  }

  func updateNSView(_ scnView: SCNView, context: Context) {
    guard let scene = scnView.scene,
          let contentNode = scene.rootNode.childNode(withName: "content", recursively: false) else { return }

    // Update camera
    if let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false) {
      Self.updateCamera(cameraNode, yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
    }

    // Update dome wireframe opacity based on camera distance
    if let domeNode = scene.rootNode.childNode(withName: "dome", recursively: false) {
      let camPos = Self.cameraWorldPosition(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
      // Use the near side of dome as representative position
      let domeNearPoint = simd_normalize(camPos) * domeRadius
      let nearDist = max(0.1, cameraDistance - domeRadius * 1.3)
      let farDist = cameraDistance + domeRadius * 1.3
      domeNode.opacity = Self.depthOpacity(position: domeNearPoint, cameraPos: camPos, near: nearDist, far: farDist) * 0.5
    }

    contentNode.childNodes.forEach { $0.removeFromParentNode() }

    let algo = IrisAlgorithm(
      bladeCount: bladeCount,
      domeRadius: domeRadius,
      tilt: tilt,
      elevation: elevation
    )

    // Distance-based opacity: compute camera position and depth range
    let camPos = Self.cameraWorldPosition(yaw: yawDegrees, pitch: pitchDegrees, distance: cameraDistance)
    let nearDist = max(0.1, cameraDistance - domeRadius * 1.3)
    let farDist = cameraDistance + domeRadius * 1.3

    let indicesToDraw = showAllBlades ? Array(0..<bladeCount) : [bladeIndex]

    for idx in indicesToDraw {
      let isSelected = idx == bladeIndex
      let color = bladeNSColor(idx, count: bladeCount)

      // Seam arc: Metal compute or Swift fallback
      let seamArc: [SIMD3<Float>]
      if let precomputed = seamArcs, idx < precomputed.count {
        seamArc = precomputed[idx]
      } else {
        seamArc = algo.seamArcPoints(index: idx, aperture: aperture)
      }
      if seamArc.count > 1 {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for (i, pt) in seamArc.enumerated() {
          vertices.append(SCNVector3(pt.x, pt.y, pt.z))
          if i > 0 {
            indices.append(Int32(i - 1))
            indices.append(Int32(i))
          }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
          data: indexData,
          primitiveType: .line,
          primitiveCount: indices.count / 2,
          bytesPerIndex: MemoryLayout<Int32>.size
        )

        let lineGeo = SCNGeometry(sources: [vertexSource], elements: [element])
        let lineMat = SCNMaterial()
        lineMat.diffuse.contents = color
        lineMat.lightingModel = .constant
        lineGeo.materials = [lineMat]
        let lineNode = SCNNode(geometry: lineGeo)
        let midIdx = seamArc.count / 2
        lineNode.opacity = Self.depthOpacity(position: seamArc[midIdx], cameraPos: camPos, near: nearDist, far: farDist)
        contentNode.addChildNode(lineNode)

        // Selected blade: add spheres along arc for thicker appearance
        if isSelected {
          let step = max(1, seamArc.count / 20)
          for i in stride(from: 0, to: seamArc.count, by: step) {
            let pt = seamArc[i]
            let bead = SCNSphere(radius: 0.008)
            bead.firstMaterial?.diffuse.contents = color
            bead.firstMaterial?.lightingModel = .constant
            let beadNode = SCNNode(geometry: bead)
            beadNode.position = SCNVector3(pt.x, pt.y, pt.z)
            beadNode.opacity = Self.depthOpacity(position: pt, cameraPos: camPos, near: nearDist, far: farDist)
            contentNode.addChildNode(beadNode)
          }
        }
      }

      // Blade normal arrow (line from origin)
      let n = algo.bladeNormal(index: idx)
      let arrowLen: Float = 0.4
      let arrowTip = SIMD3<Float>(n.x * arrowLen, n.y * arrowLen, n.z * arrowLen)
      let arrowVerts = [
        SCNVector3(0, 0, 0),
        SCNVector3(arrowTip.x, arrowTip.y, arrowTip.z)
      ]
      let arrowIndices: [Int32] = [0, 1]
      let arrowSource = SCNGeometrySource(vertices: arrowVerts)
      let arrowIndexData = Data(bytes: arrowIndices, count: arrowIndices.count * MemoryLayout<Int32>.size)
      let arrowElement = SCNGeometryElement(
        data: arrowIndexData,
        primitiveType: .line,
        primitiveCount: 1,
        bytesPerIndex: MemoryLayout<Int32>.size
      )
      let arrowGeo = SCNGeometry(sources: [arrowSource], elements: [arrowElement])
      let arrowMat = SCNMaterial()
      arrowMat.diffuse.contents = color
      arrowMat.lightingModel = .constant
      arrowGeo.materials = [arrowMat]
      let arrowNode = SCNNode(geometry: arrowGeo)
      arrowNode.opacity = Self.depthOpacity(position: arrowTip * 0.5, cameraPos: camPos, near: nearDist, far: farDist)
      contentNode.addChildNode(arrowNode)

      // Sphere at arrow tip
      let tipRadius: CGFloat = isSelected ? 0.025 : 0.02
      let tipSphere = SCNSphere(radius: tipRadius)
      tipSphere.firstMaterial?.diffuse.contents = color
      tipSphere.firstMaterial?.lightingModel = .constant
      let tipNode = SCNNode(geometry: tipSphere)
      tipNode.position = SCNVector3(arrowTip.x, arrowTip.y, arrowTip.z)
      tipNode.opacity = Self.depthOpacity(position: arrowTip, cameraPos: camPos, near: nearDist, far: farDist)
      contentNode.addChildNode(tipNode)

      // Seam point
      if let sp = algo.seamPoint(bladeIndex: idx, aperture: aperture) {
        let seamRadius: CGFloat = isSelected ? 0.03 : 0.025
        let seamSphere = SCNSphere(radius: seamRadius)
        seamSphere.firstMaterial?.diffuse.contents = NSColor.white
        seamSphere.firstMaterial?.lightingModel = .constant
        let seamNode = SCNNode(geometry: seamSphere)
        seamNode.position = SCNVector3(sp.x, sp.y, sp.z)
        seamNode.opacity = Self.depthOpacity(position: sp, cameraPos: camPos, near: nearDist, far: farDist)
        contentNode.addChildNode(seamNode)
      }
    }

    // Sample points colored by blade ownership
    if showSamples {
      let R = domeRadius
      let sLatSteps = ownershipLatSteps
      let sLonSteps = ownershipLonSteps
      for lat in 0..<sLatSteps {
        let theta = Float(lat) * (Float.pi / 2.0) / Float(sLatSteps)
        for lon in 0..<sLonSteps {
          let phi = Float(lon) * 2.0 * Float.pi / Float(sLonSteps)
          let Q = R * SIMD3<Float>(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))

          let blade: Int?
          if let own = ownership {
            let oi = lat * sLonSteps + lon
            blade = own[oi] >= 0 ? Int(own[oi]) : nil
          } else {
            blade = algo.findVisibleBlade(Q: Q, aperture: aperture)
          }

          let sampleSphere = SCNSphere(radius: 0.012)
          if let b = blade {
            sampleSphere.firstMaterial?.diffuse.contents = bladeNSColor(b, count: bladeCount, alpha: 0.7)
          } else {
            sampleSphere.firstMaterial?.diffuse.contents = NSColor.gray.withAlphaComponent(0.3)
          }
          sampleSphere.firstMaterial?.lightingModel = .constant
          let sampleNode = SCNNode(geometry: sampleSphere)
          sampleNode.position = SCNVector3(Q.x, Q.y, Q.z)
          sampleNode.opacity = Self.depthOpacity(position: Q, cameraPos: camPos, near: nearDist, far: farDist)
          contentNode.addChildNode(sampleNode)
        }
      }
    }
  }
}

#Preview {
  IrisDebugView()
    .frame(width: 1100, height: 600)
}
