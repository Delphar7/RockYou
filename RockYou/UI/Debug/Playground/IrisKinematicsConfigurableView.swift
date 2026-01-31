// IrisKinematicsConfigurableView.swift
// RockYou
//
// Configurable iris kinematics debug view.
// All geometry derived from basic inputs: Rin, Rout, Length, bladeCount.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct IrisKinematicsConfigurableView: View {
  // MARK: - Configurable Inputs

    @State private var rin: Double = 45.0  // Inner arc radius from P
    @State private var rout: Double = 50.0  // Outer arc radius from P
    @State private var lengthDeg: Double = 90.0  // Arc angle in degrees
    @State private var bladeCount: Int = 12

  // Actuator rotation range (degrees)
    @State private var maxActuatorRotationDeg: Double = 90.0  // Rotation at closed position

    // Animation parameter: 0 = open, 1 = closed
  @State private var aperture: Double = 0.0
  @State private var isAnimating: Bool = false

  // Display options
  @State private var showPivotCircle: Bool = true
  @State private var showSlots: Bool = true
  @State private var showPivots: Bool = true
  @State private var showActuatorPins: Bool = true
  @State private var showBladeP: Bool = false
  @State private var visibleBlades: [Bool] = Array(repeating: true, count: 12)

  @State private var animationTimer: Timer?

  // MARK: - Computed Geometry

  private var lengthRad: Double { lengthDeg * .pi / 180 }
  private var rm: Double { (rin + rout) / 2 }
  private var endcapRadius: Double { (rout - rin) / 2 }
  private var pivotToActuator: Double { 2 * rm * sin(lengthRad / 2) }
  private var pivotRadius: Double { rm }  // Pivot mounting circle radius

  // Blade-local coordinates (pivot at origin)
  private var bladeP: SIMD2<Double> { SIMD2(-rm, 0) }
  private var bladePivotPin: SIMD2<Double> { SIMD2(0, 0) }
  private var bladeActuatorPin: SIMD2<Double> {
    SIMD2(rm * (cos(lengthRad) - 1), rm * sin(lengthRad))
  }

  // Slot geometry: derived from blade geometry
  // These define the radial extent of the slots on the actuator ring
  private var slotInnerRadius: Double { pivotRadius - pivotToActuator * 0.8 }
  private var slotOuterRadius: Double { pivotRadius + pivotToActuator * 0.8 }

  // Slot base angles: computed such that at t=0, actuator pins sit exactly on the Rm circle.
  // When actuator is at angle (pivotAngle + Length) on Rm circle, the chord length
  // from pivot to actuator equals 2*Rm*sin(Length/2) = pivotToActuator.
  private func slotBaseAngle(for bladeIndex: Int) -> Double {
    let pivotAngle = Double(bladeIndex) * (2 * .pi / Double(bladeCount))
    return pivotAngle + lengthRad
  }

    private var maxActuatorRotationRad: Double { -maxActuatorRotationDeg * .pi / 180 }

  var body: some View {
    HSplitView {
      // Left: Canvas drawing
      GeometryReader { geo in
        Canvas { context, size in
          drawIris(context: context, size: size)
        }
        .background(Color.black.opacity(0.9))
      }
      .frame(minWidth: 400, minHeight: 400)

      // Right: Controls
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          geometryInputsSection
          derivedValuesSection
          apertureControlSection
          kinematicsInfoSection
          displayOptionsSection
          bladesSection
        }
        .padding()
      }
      .frame(width: 300)
    }
    .onDisappear {
      animationTimer?.invalidate()
    }
    .onChange(of: bladeCount) { _, newCount in
      // Resize visibleBlades array when blade count changes
      if newCount > visibleBlades.count {
        visibleBlades.append(contentsOf: Array(repeating: true, count: newCount - visibleBlades.count))
      } else if newCount < visibleBlades.count {
        visibleBlades = Array(visibleBlades.prefix(newCount))
      }
    }
  }

  // MARK: - Kinematics

  private func actuatorRotation(for aperture: Double) -> Double {
    // aperture 0 = open (rotation = 0)
    // aperture 1 = closed (rotation = -maxActuatorRotationRad, pulling blades inward)
    return -aperture * maxActuatorRotationRad
  }

  private func bladeAngle(
    bladeIndex: Int,
    actuatorRotation: Double
  ) -> (bladeAngle: Double, actuatorRadius: Double, isValid: Bool)? {
    guard bladeIndex < bladeCount else { return nil }

    let pivotAngle = Double(bladeIndex) * (2 * .pi / Double(bladeCount))
    let pivotX = pivotRadius * cos(pivotAngle)
    let pivotY = pivotRadius * sin(pivotAngle)

    let slotAngle = slotBaseAngle(for: bladeIndex) + actuatorRotation

    // Solve for actuator pin position along slot line
    // The slot is a radial line at angle slotAngle
    // Actuator pin is at distance pivotToActuator from pivot
    // Find radius r where: |pivot - (r*cos(slotAngle), r*sin(slotAngle))| = pivotToActuator
    //
    // Expanding: (pivotX - r*cos(θ))² + (pivotY - r*sin(θ))² = d²
    // pivotX² - 2*pivotX*r*cos(θ) + r²*cos²(θ) + pivotY² - 2*pivotY*r*sin(θ) + r²*sin²(θ) = d²
    // r² - 2r(pivotX*cos(θ) + pivotY*sin(θ)) + (pivotX² + pivotY²) - d² = 0
    // r² - 2r*dot + (pivotRadius² - d²) = 0

    let d = pivotToActuator
    let dot = pivotX * cos(slotAngle) + pivotY * sin(slotAngle)
    let c = pivotRadius * pivotRadius - d * d

    let discriminant = dot * dot - c

    guard discriminant >= 0 else {
      return (0, 0, false)  // No valid solution
    }

    let sqrtDisc = sqrt(discriminant)
    let r1 = dot + sqrtDisc
    let r2 = dot - sqrtDisc

    let slotInner = slotInnerRadius
    let slotOuter = slotOuterRadius

    var r: Double
    let inRange1 = r1 >= slotInner && r1 <= slotOuter
    let inRange2 = r2 >= slotInner && r2 <= slotOuter

    if inRange1 && !inRange2 {
      r = r1
    } else if inRange2 && !inRange1 {
      r = r2
    } else if inRange1 && inRange2 {
      let slotMid = (slotInner + slotOuter) / 2
      r = abs(r1 - slotMid) < abs(r2 - slotMid) ? r1 : r2
    } else {
      let d1 = min(abs(r1 - slotInner), abs(r1 - slotOuter))
      let d2 = min(abs(r2 - slotInner), abs(r2 - slotOuter))
      r = d1 < d2 ? r1 : r2
    }

    let actuatorX = r * cos(slotAngle)
    let actuatorY = r * sin(slotAngle)

    // θ_world: angle from pivot to actuator in world coords
    let thetaWorld = atan2(actuatorY - pivotY, actuatorX - pivotX)

    // θ_local: angle of actuator pin in blade-local coords (pivot at origin)
    // bladeActuatorPin = (rm * (cos(L) - 1), rm * sin(L))
    let thetaLocal = atan2(sin(lengthRad), cos(lengthRad) - 1)

    // Blade rotation needed to place local actuator at world position
    let bladeAngle = thetaWorld - thetaLocal

    let isValid = r >= slotInner && r <= slotOuter

    return (bladeAngle, r, isValid)
  }

  // MARK: - Drawing

  private func drawIris(context: GraphicsContext, size: CGSize) {
    let padding: CGFloat = 40
    let availableSize = min(size.width, size.height) - padding * 2

    // Scale to fit the iris with some margin
    let maxExtent = pivotRadius + rout + 10
    let scale = availableSize / (maxExtent * 2)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)

    func toView(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: center.x + point.x * scale,
        y: center.y - point.y * scale  // Flip Y
      )
    }

    func toViewRadius(_ r: CGFloat) -> CGFloat {
      r * scale
    }

    let actuatorRot = actuatorRotation(for: aperture)

    // Draw pivot mounting circle
    if showPivotCircle {
      let circleR = toViewRadius(pivotRadius)
      let circleRect = CGRect(
        x: center.x - circleR, y: center.y - circleR,
        width: circleR * 2, height: circleR * 2
      )
      context.stroke(Path(ellipseIn: circleRect), with: .color(.gray.opacity(0.5)), lineWidth: 1)
    }

    // Draw slots (rotate with actuator)
    if showSlots {
      for i in 0..<bladeCount {
        let slotAngle = slotBaseAngle(for: i) + actuatorRot
        let innerPt = CGPoint(x: slotInnerRadius * cos(slotAngle), y: slotInnerRadius * sin(slotAngle))
        let outerPt = CGPoint(x: slotOuterRadius * cos(slotAngle), y: slotOuterRadius * sin(slotAngle))

        var slotPath = Path()
        slotPath.move(to: toView(innerPt))
        slotPath.addLine(to: toView(outerPt))
          context.stroke(slotPath, with: .color(.blue.opacity(0.33)), lineWidth: 1)
      }
    }

    // Draw pivots
    if showPivots {
      let pivotVisRadius = toViewRadius(1.5)
      for i in 0..<bladeCount {
        let angle = Double(i) * (2 * .pi / Double(bladeCount))
        let pivotPt = CGPoint(x: pivotRadius * cos(angle), y: pivotRadius * sin(angle))
        let viewPt = toView(pivotPt)
        let pivotRect = CGRect(
          x: viewPt.x - pivotVisRadius,
          y: viewPt.y - pivotVisRadius,
          width: pivotVisRadius * 2,
          height: pivotVisRadius * 2
        )
        context.fill(Path(ellipseIn: pivotRect), with: .color(.red))
      }
    }

    // Draw blades
    for i in 0..<bladeCount where i < visibleBlades.count && visibleBlades[i] {
      if let result = bladeAngle(bladeIndex: i, actuatorRotation: actuatorRot) {
        drawBlade(
          context: context,
          bladeIndex: i,
          bladeAngle: result.bladeAngle,
          toView: toView,
          scale: scale,
          isValid: result.isValid
        )
      }
    }

    // Draw center indicator
    let apertureText = String(format: "t = %.2f", aperture)
    context.draw(
      Text(apertureText).font(.system(.caption, design: .monospaced)).foregroundColor(.white),
      at: center
    )
  }

  private func drawBlade(
    context: GraphicsContext,
    bladeIndex: Int,
    bladeAngle: Double,
    toView: (CGPoint) -> CGPoint,
    scale: CGFloat,
    isValid: Bool
  ) {
    let pivotAngle = Double(bladeIndex) * (2 * .pi / Double(bladeCount))
    let pivotPos = CGPoint(x: pivotRadius * cos(pivotAngle), y: pivotRadius * sin(pivotAngle))

    // Transform blade-local point to world
    func bladeToWorld(_ localPt: SIMD2<Double>) -> CGPoint {
      let cos_a = cos(bladeAngle)
      let sin_a = sin(bladeAngle)
      let rotX = localPt.x * cos_a - localPt.y * sin_a
      let rotY = localPt.x * sin_a + localPt.y * cos_a
      return CGPoint(x: pivotPos.x + rotX, y: pivotPos.y + rotY)
    }

    let pWorld = bladeToWorld(bladeP)
    let pivotPinWorld = bladeToWorld(bladePivotPin)
    let actuatorPinWorld = bladeToWorld(bladeActuatorPin)

    // Calculate angles from P in world coords
    let angleToPivot = atan2(pivotPinWorld.y - pWorld.y, pivotPinWorld.x - pWorld.x)
    let angleToActuator = atan2(actuatorPinWorld.y - pWorld.y, actuatorPinWorld.x - pWorld.x)

    // Determine arc direction
    var delta = angleToPivot - angleToActuator
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    let arcClockwise = delta > 0

    let pView = toView(pWorld)
    let pivotView = toView(pivotPinWorld)
    let actuatorView = toView(actuatorPinWorld)

    let riScaled = rin * scale
    let roScaled = rout * scale
    let endcapScaled = endcapRadius * scale

    var bladePath = Path()

    // 1. Inner arc: actuator to pivot (centered at P)
    let innerStart = Angle(radians: -angleToActuator)
    let innerEnd = Angle(radians: -angleToPivot)
    bladePath.addArc(
      center: pView, radius: riScaled,
      startAngle: innerStart, endAngle: innerEnd,
      clockwise: arcClockwise)

    // 2. Pivot endcap (bulges away from P)
    let pivotCapStart = Angle(radians: -(angleToPivot + .pi))
    let pivotCapEnd = Angle(radians: -angleToPivot)
    bladePath.addArc(
      center: pivotView, radius: endcapScaled,
      startAngle: pivotCapStart, endAngle: pivotCapEnd,
      clockwise: true)

    // 3. Outer arc: pivot to actuator (centered at P)
    let outerStart = Angle(radians: -angleToPivot)
    let outerEnd = Angle(radians: -angleToActuator)
    bladePath.addArc(
      center: pView, radius: roScaled,
      startAngle: outerStart, endAngle: outerEnd,
      clockwise: !arcClockwise)

    // 4. Actuator endcap (bulges away from P)
    let actCapStart = Angle(radians: -angleToActuator)
    let actCapEnd = Angle(radians: -(angleToActuator + .pi))
    bladePath.addArc(
      center: actuatorView, radius: endcapScaled,
      startAngle: actCapStart, endAngle: actCapEnd,
      clockwise: true)

    bladePath.closeSubpath()

    // Color by blade index
    let hue = Double(bladeIndex) / Double(bladeCount)
    let bladeColor = Color(hue: hue, saturation: 0.8, brightness: 0.9)

      let fillAlpha = isValid ? 0.25 : 0.05
    context.fill(bladePath, with: .color(bladeColor.opacity(fillAlpha)))
    context.stroke(bladePath, with: .color(bladeColor), lineWidth: 1.5)

    // Draw actuator pin
    if showActuatorPins {
      let pinRadius: CGFloat = 3
      let pinRect = CGRect(
        x: actuatorView.x - pinRadius,
        y: actuatorView.y - pinRadius,
        width: pinRadius * 2,
        height: pinRadius * 2
      )
      context.fill(Path(ellipseIn: pinRect), with: .color(isValid ? .cyan : .red))
    }

    // Draw P point
    if showBladeP {
      let pRadius: CGFloat = 2
      let pRect = CGRect(
        x: pView.x - pRadius,
        y: pView.y - pRadius,
        width: pRadius * 2,
        height: pRadius * 2
      )
      context.fill(Path(ellipseIn: pRect), with: .color(.yellow))
    }
  }

  // MARK: - UI Sections

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

  private var derivedValuesSection: some View {
    GroupBox("Derived Values") {
      VStack(alignment: .leading, spacing: 4) {
        LabeledContent("Rm (mid-radius)") {
          Text(String(format: "%.2f", rm))
        }
        LabeledContent("Endcap radius") {
          Text(String(format: "%.2f", endcapRadius))
        }
        LabeledContent("Pivot-to-actuator") {
          Text(String(format: "%.2f", pivotToActuator))
        }
        LabeledContent("Pivot circle radius") {
          Text(String(format: "%.2f", pivotRadius))
        }
        LabeledContent("Slot inner radius") {
          Text(String(format: "%.2f", slotInnerRadius))
        }
        LabeledContent("Slot outer radius") {
          Text(String(format: "%.2f", slotOuterRadius))
        }
      }
      .font(.system(.caption, design: .monospaced))
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
          Button(isAnimating ? "Stop" : "Animate") {
            toggleAnimation()
          }
          .buttonStyle(.bordered)
        }

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
    }
  }

  private var kinematicsInfoSection: some View {
    GroupBox("Kinematics") {
      VStack(alignment: .leading, spacing: 4) {
        let actuatorRot = actuatorRotation(for: aperture)
        LabeledContent("Actuator Rotation") {
          Text(String(format: "%.2f°", actuatorRot * 180 / .pi))
        }

        // Show info for first visible blade
        let firstVisible = visibleBlades.firstIndex(of: true) ?? 0
        if let result = bladeAngle(bladeIndex: firstVisible, actuatorRotation: actuatorRot) {
          LabeledContent("Blade \(firstVisible) Angle") {
            Text(String(format: "%.2f°", result.bladeAngle * 180 / .pi))
          }
          LabeledContent("Actuator Radius") {
            Text(String(format: "%.2f", result.actuatorRadius))
          }
          LabeledContent("Valid") {
            Text(result.isValid ? "Yes" : "No")
              .foregroundColor(result.isValid ? .green : .red)
          }
        }
      }
      .font(.system(.caption, design: .monospaced))
    }
  }

  private var displayOptionsSection: some View {
    GroupBox("Display Options") {
      VStack(alignment: .leading, spacing: 8) {
        Toggle("Pivot Circle", isOn: $showPivotCircle)
        Toggle("Actuator Slots", isOn: $showSlots)
        Toggle("Pivot Points", isOn: $showPivots)
        Toggle("Actuator Pins", isOn: $showActuatorPins)
        Toggle("Blade Center (P)", isOn: $showBladeP)
      }
    }
  }

  private var bladesSection: some View {
    GroupBox("Blades") {
      VStack(spacing: 8) {
        // Grid of checkboxes (4 rows x 3 cols for 12 blades, adapts to bladeCount)
        let cols = 3
        let rows = (bladeCount + cols - 1) / cols
        ForEach(0..<rows, id: \.self) { row in
          HStack(spacing: 12) {
            ForEach(0..<cols, id: \.self) { col in
              let idx = row * cols + col
              if idx < bladeCount && idx < visibleBlades.count {
                bladeToggle(index: idx)
              }
            }
          }
        }

        Divider()

        HStack {
          Button("All") {
            for i in 0..<min(bladeCount, visibleBlades.count) {
              visibleBlades[i] = true
            }
          }
          .buttonStyle(.bordered)

          Button("None") {
            for i in 0..<min(bladeCount, visibleBlades.count) {
              visibleBlades[i] = false
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func bladeToggle(index: Int) -> some View {
    let hue = Double(index) / Double(max(1, bladeCount))
    let color = Color(hue: hue, saturation: 0.8, brightness: 0.9)

    return Toggle(isOn: $visibleBlades[index]) {
      HStack(spacing: 4) {
        Circle()
          .fill(color)
          .frame(width: 10, height: 10)
        Text("\(index)")
          .font(.caption)
          .monospacedDigit()
      }
    }
    .toggleStyle(.checkbox)
  }

  // MARK: - Animation

  private func toggleAnimation() {
    if isAnimating {
      animationTimer?.invalidate()
      animationTimer = nil
      isAnimating = false
    } else {
      isAnimating = true
      var direction: Double = 1.0
      animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
        aperture += 0.008 * direction
        if aperture >= 1.0 {
          aperture = 1.0
          direction = -1.0
        } else if aperture <= 0.0 {
          aperture = 0.0
          direction = 1.0
        }
      }
    }
  }
}

#Preview("Iris Configurable") {
  IrisKinematicsConfigurableView()
    .frame(width: 950, height: 700)
}
