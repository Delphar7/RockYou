// IrisSeamEquationsMaskDebugView.swift
// RockYou
//
// Equation-only iris mask debug view (no geometry).
//
// NOTE: This is REFERENCE CODE for kinematics visualization, not intended for production.
// The production iris uses IrisAlgorithm.h (GPU shader) with a simpler pivot+distance model.
// This view uses the "slot/actuator" kinematics model from IrisKinematicsModel.swift.

#if os(macOS)

import CoreGraphics
import SwiftUI
import simd

struct IrisSeamEquationsMaskDebugView: View {
  @State private var rin: Double = 45.0
  @State private var rout: Double = 50.0
  @State private var lengthDeg: Double = 90.0
  @State private var bladeCount: Int = 12
  @State private var maxActuatorRotationDeg: Double = 90.0
  @State private var aperture: Double = 0.0
  @State private var edgeSoftness: Double = 0.6
  @State private var seamWidth: Double = 0.8
  @State private var seamSoftness: Double = 0.9
  @State private var showSeams: Bool = true
  @State private var maskImage: CGImage?

  private let imageSize: Int = 640

  private var model: IrisKinematicsModel {
    IrisKinematicsModel(
      rin: rin,
      rout: rout,
      lengthDeg: lengthDeg,
      bladeCount: bladeCount,
      maxActuatorRotationDeg: maxActuatorRotationDeg,
      slotInnerScale: 0.8,
      slotOuterScale: 0.2
    )
  }

  var body: some View {
    HSplitView {
      ZStack {
        Color.black.opacity(0.9)
        if let maskImage {
          Image(decorative: maskImage, scale: 1)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .padding(12)
        } else {
          ProgressView()
        }
      }
      .overlay(alignment: .topLeading) {
        Text("Equation Mask Playground")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.white.opacity(0.7))
          .padding(8)
      }
      .frame(minWidth: 400, minHeight: 400)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          geometryInputsSection
          apertureControlSection
          maskOptionsSection
        }
        .padding()
      }
      .frame(width: 300)
    }
    .onAppear(perform: refreshImage)
    .onChange(of: rin) { _, _ in refreshImage() }
    .onChange(of: rout) { _, _ in refreshImage() }
    .onChange(of: lengthDeg) { _, _ in refreshImage() }
    .onChange(of: bladeCount) { _, _ in refreshImage() }
    .onChange(of: maxActuatorRotationDeg) { _, _ in refreshImage() }
    .onChange(of: aperture) { _, _ in refreshImage() }
    .onChange(of: edgeSoftness) { _, _ in refreshImage() }
    .onChange(of: seamWidth) { _, _ in refreshImage() }
    .onChange(of: seamSoftness) { _, _ in refreshImage() }
    .onChange(of: showSeams) { _, _ in refreshImage() }
  }

  private var geometryInputsSection: some View {
    GroupBox("Blade Geometry") {
      VStack(alignment: .leading, spacing: 10) {
        LabeledContent("Rin (inner radius)") {
          HStack {
            Slider(value: $rin, in: 5...50)
            Text(String(format: "%.1f", rin))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 40)
          }
        }

        LabeledContent("Rout (outer radius)") {
          HStack {
            Slider(value: $rout, in: 10...60)
            Text(String(format: "%.1f", rout))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 40)
          }
        }

        LabeledContent("Length (arc angle)") {
          HStack {
            Slider(value: $lengthDeg, in: 10...120)
            Text(String(format: "%.0f°", lengthDeg))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 40)
          }
        }

        LabeledContent("Blade Count") {
          Stepper("\(bladeCount)", value: $bladeCount, in: 3...24)
        }

        Divider()

        LabeledContent("Max Rotation (closed)") {
          HStack {
            Slider(value: $maxActuatorRotationDeg, in: 0...180)
            Text(String(format: "%.0f°", maxActuatorRotationDeg))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 40)
          }
        }
      }
    }
  }

  private var apertureControlSection: some View {
    GroupBox("Aperture Control") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Open").font(.caption)
          Slider(value: $aperture, in: 0...1)
          Text("Closed").font(.caption)
        }

        HStack {
          Text(String(format: "t = %.3f", aperture))
            .font(.system(.body, design: .monospaced))
          Spacer()
        }
      }
    }
  }

  private var maskOptionsSection: some View {
    GroupBox("Mask Options") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("Show Seams", isOn: $showSeams)

        LabeledContent("Edge Softness") {
          HStack {
            Slider(value: $edgeSoftness, in: 0.0...2.0)
            Text(String(format: "%.2f", edgeSoftness))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 50)
          }
        }

        LabeledContent("Seam Width") {
          HStack {
            Slider(value: $seamWidth, in: 0.0...3.0)
            Text(String(format: "%.2f", seamWidth))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 50)
          }
        }

        LabeledContent("Seam Softness") {
          HStack {
            Slider(value: $seamSoftness, in: 0.0...3.0)
            Text(String(format: "%.2f", seamSoftness))
              .font(.system(.caption, design: .monospaced))
              .frame(width: 50)
          }
        }
      }
    }
  }

  private func refreshImage() {
    maskImage = makeEquationMaskImage(size: imageSize)
  }

  private func makeEquationMaskImage(size: Int) -> CGImage? {
    let width = max(1, size)
    let height = max(1, size)
    var buffer = [UInt8](repeating: 0, count: width * height * 4)

    let extent = model.pivotRadius + model.rout
    let actuatorRot = model.actuatorRotation(for: aperture)

    let invW = 1.0 / Double(width)
    let invH = 1.0 / Double(height)

    for y in 0..<height {
      let v = (Double(y) + 0.5) * invH
      let py = (1 - v) * 2 - 1

      for x in 0..<width {
        let u = (Double(x) + 0.5) * invW
        let px = u * 2 - 1

        let worldX = px * extent
        let worldY = py * extent
        let p = SIMD2<Double>(worldX, worldY)

        let r = simd_length(p)
        let baseDisc = r <= extent ? 1.0 : 0.0

        var minSignedDist = Double.greatestFiniteMagnitude
        var winnerIndex: Int?
        var winnerSeamDist: Double = 0

        for i in 0..<model.bladeCount {
          guard let bladeResult = model.bladeAngle(
            bladeIndex: i,
            actuatorRotation: actuatorRot
          ) else { continue }

          let pivotPos = model.pivotPosition(for: i)
          let local = rotateToLocal(p - pivotPos, angle: bladeResult.bladeAngle)
          let vLocal = local - model.bladeP
          let dist = simd_length(vLocal)
          let phi = normalizeAngle(atan2(vLocal.y, vLocal.x))
          guard phi >= 0 && phi <= model.lengthRad else { continue }

          let signedDist = model.rin - dist
          if signedDist < minSignedDist {
            minSignedDist = signedDist
            winnerIndex = i
            winnerSeamDist = abs(dist - model.rin)
          }
        }

        let apertureMask: Double
        if minSignedDist == Double.greatestFiniteMagnitude {
          apertureMask = 0
        } else {
          apertureMask = smoothstep(
            edge0: -edgeSoftness,
            edge1: edgeSoftness,
            x: minSignedDist
          )
        }

        let coverage = clamp01(baseDisc * (1 - apertureMask))

        var seam = 0.0
        if showSeams, winnerIndex != nil {
          seam = 1 - smoothstep(
            edge0: seamWidth,
            edge1: seamWidth + seamSoftness,
            x: winnerSeamDist
          )
        }

        let seamIntensity = seam * coverage
        let baseColor = bladeColor(for: winnerIndex ?? 0, bladeCount: model.bladeCount)
        let color = mixColor(baseColor, (1, 1, 1), t: seamIntensity)

        let alpha = coverage
        let offset = (y * width + x) * 4
        buffer[offset + 0] = UInt8(clamp01(color.r * alpha) * 255)
        buffer[offset + 1] = UInt8(clamp01(color.g * alpha) * 255)
        buffer[offset + 2] = UInt8(clamp01(color.b * alpha) * 255)
        buffer[offset + 3] = UInt8(clamp01(alpha) * 255)
      }
    }

    let data = Data(buffer)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func rotateToLocal(_ p: SIMD2<Double>, angle: Double) -> SIMD2<Double> {
    let c = cos(angle)
    let s = sin(angle)
    return SIMD2(c * p.x + s * p.y, -s * p.x + c * p.y)
  }

  private func normalizeAngle(_ angle: Double) -> Double {
    let twoPi = 2 * Double.pi
    var a = angle.truncatingRemainder(dividingBy: twoPi)
    if a < 0 { a += twoPi }
    return a
  }

  private func clamp01(_ x: Double) -> Double {
    min(1, max(0, x))
  }

  private func smoothstep(edge0: Double, edge1: Double, x: Double) -> Double {
    let denom = max(1e-6, edge1 - edge0)
    let t = clamp01((x - edge0) / denom)
    return t * t * (3 - 2 * t)
  }

  private func bladeColor(for index: Int, bladeCount: Int) -> (r: Double, g: Double, b: Double) {
    let hue = Double(index) / Double(max(1, bladeCount))
    return hsvToRgb(h: hue, s: 0.8, v: 0.9)
  }

  private func hsvToRgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
    let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
    let i = Int(hh * 6)
    let f = hh * 6 - Double(i)
    let p = v * (1 - s)
    let q = v * (1 - f * s)
    let t = v * (1 - (1 - f) * s)
    switch i % 6 {
    case 0: return (v, t, p)
    case 1: return (q, v, p)
    case 2: return (p, v, t)
    case 3: return (p, q, v)
    case 4: return (t, p, v)
    default: return (v, p, q)
    }
  }

  private func mixColor(
    _ a: (r: Double, g: Double, b: Double),
    _ b: (r: Double, g: Double, b: Double),
    t: Double
  ) -> (r: Double, g: Double, b: Double) {
    let tt = clamp01(t)
    return (
      a.r * (1 - tt) + b.r * tt,
      a.g * (1 - tt) + b.g * tt,
      a.b * (1 - tt) + b.b * tt
    )
  }
}

#Preview("Iris Seam Equations Mask") {
  IrisSeamEquationsMaskDebugView()
    .frame(width: 950, height: 700)
}

#endif  // os(macOS)
