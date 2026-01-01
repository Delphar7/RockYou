//
//  DPadView.swift
//  RockYou (Shared)
//
//  Swipe-from-center D-pad with auto-repeat based on drag distance.
//  Works on watchOS, iOS, and macOS.
//  See UX-Design.md for interaction details.
//

import SwiftUI

struct DPadView: View {
  let onDirection: (RemoteAction) -> Void
  let onOK: () -> Void
  var size: CGFloat? = nil  // If nil, uses frame size

  // MARK: - Configuration

  private let activationThreshold: CGFloat = 20  // Min drag to register direction
  private let okDeadZone: CGFloat = 8  // Drag less than this = OK tap
  private let angularTolerance: CGFloat = 30  // Degrees from cardinal direction

  // Tap regions (relative to rendered D-pad art size)
  private let arrowTapInnerRadiusFractionOfSize: CGFloat = 0.24
  private let arrowTapOuterRadiusFractionOfSize: CGFloat = 0.64
  private let arrowTapAxisHalfWidthFractionOfSize: CGFloat = 0.18
  /// "Angle of reach" for arrow tap regions. Positive values widen the region as distance increases
  /// (isosceles trapezoid). 0 means straight rectangle.
  private let arrowTapReachAngleDegrees: CGFloat = 8
  // Debug: visualize the tap regions so they can be tuned by eye.
  private let debugShowTapRegions: Bool = false

  // Visual tuning (art-driven)
  /// Treat the physical drag range as 0..(2R) == 0..size, and move the stick at half that distance.
  private let stickVisualMovementScale: CGFloat = 0.5
  /// Clamp the stick's maximum visual travel so it doesn't "fly away" from the base.
  /// This preserves the original feel: baseRadiusFractionOfSize (0.16) with maxPastEdge (0.33)
  /// => 0.16 * (1 + 0.33) ~= 0.2128 of the rendered DPad art size.
  private let stickMaxVisualTravelFractionOfSize: CGFloat = 0.213
  /// Shadow vertical motion relative to the stick (applied to both up and down).
  private let shadowVerticalRate: CGFloat = 0.66
  /// Clip line for the shadow, relative to the stick's midpoint (in the DPad's local coordinates).
  /// 0 means "midpoint == the center of the stick image". Tweak if the art's midpoint isn't exact.
  private let stickShadowClipMidpointYOffsetFractionOfSize: CGFloat = -0.06
  /// Tap-region centerline relative to the DPad base center.
  /// Empirically this should be about **½** the shadow-clip midpoint offset: the stick “head” isn’t centered on the base.
  /// This likely does not need tuning; keep it tied to the art-driven shadow midpoint.
  private let tapCenterlineMultiplierOfShadowMidpoint: CGFloat = 0.5
  /// "OK" label font size, relative to the DPad art size used for rendering the PNG stack.
  /// This is intentionally tied to the same coordinate space as the stick + shadow clip midpoint.
  private let okLabelFontFractionOfSize: CGFloat = 0.11
  /// Extra visual-only nudge for the "OK" label (positive = down).
  private let okLabelExtraYOffsetFractionOfSize: CGFloat = 0.01

  // Press feedback (visual only)
  private let stickPressScale: CGFloat = 0.975
  private let stickPressYOffsetFractionOfSize: CGFloat = 0.04
  private let stickPressAnimation: Animation = .spring(response: 0.18, dampingFraction: 0.86)

  // MARK: - State

  @State private var dragOffset: CGSize = .zero
  @State private var currentDirection: RemoteAction?
  @State private var repeatTimer: Timer?
  @State private var tapHoldTimer: Timer?
  @State private var tapHoldStartedAt: Date?
  @State private var tapHoldDirection: RemoteAction?
  @State private var isDragging = false
  @State private var isInDragMode = false
  @State private var hasFiredDirection = false  // Track if any direction was sent
  @State private var isPressingOK = false  // Visual-only: stick press should only occur for OK-region touches

  var body: some View {
    if let explicitSize = size {
      // Explicit size provided
      okButtonView(size: explicitSize)
    } else {
      // Use frame size
      GeometryReader { geo in
        let buttonSize = min(geo.size.width, geo.size.height)
        okButtonView(size: buttonSize)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private func okButtonView(size: CGFloat) -> some View {
    return ZStack {
      okButton(size: size)
    }
    .frame(width: size, height: size)
  }

  // MARK: - OK Button

  private func okButton(size: CGFloat) -> some View {
    let stickOffset = stickOffsetForVisual(size: size)
    let shadowOffset = shadowOffsetForVisual(stickOffset: stickOffset)
    let shadowClipMidpointYOffset = size * stickShadowClipMidpointYOffsetFractionOfSize
    let okLabelFontSize = max(10, size * okLabelFontFractionOfSize)
    let okLabelYOffset = shadowClipMidpointYOffset + (size * okLabelExtraYOffsetFractionOfSize)
    // "Pressed" is a visual-only state: press down on touch-down, but pop back up once we
    // transition into real drag mode.
    let stickPressed = isDragging && !isInDragMode && isPressingOK
    let stickPressYOffset = stickPressed ? (size * stickPressYOffsetFractionOfSize) : 0

    return ZStack {
      // Base layers (these are aligned relative to each other in the PNGs)
      dpadLayer(named: "DPad-Ring", size: size)

      // Shadow directly under the stick.
      // Render under the stick. The stick being drawn above naturally occludes/clips it.
      // (Masking by the stick silhouette can fully hide this asset, since it's a "ground shadow".)
      dpadLayer(named: "StickShadow", size: size)
        .offset(shadowOffset)
        .blendMode(.multiply)
        .opacity(stickPressed ? 1.0 : 0.95)
        // Prevent the shadow from ever rendering above the stick's midpoint (plus an optional tweak).
        // This allows the shadow PNG to be extended upward without causing a "shadow sticking out"
        // when the stick is at rest or moved down.
        .mask(
          shadowClipMask(
            size: size, stickOffset: stickOffset, midpointYOffset: shadowClipMidpointYOffset))

      // Stick on top (with "OK" label baked into the same offset group, so it moves exactly with the stick).
      ZStack {
        dpadLayer(named: "Stick", size: size)
        Text("OK")
          .font(.system(size: okLabelFontSize, weight: .bold, design: .rounded))
          .foregroundStyle(Color.black.opacity(0.8))
          // Helps readability over the stick highlight without looking "outlined".
          .shadow(color: Color.white.opacity(0.25), radius: 0, x: -0.5, y: 1)
          .offset(x: 0, y: okLabelYOffset)
          .allowsHitTesting(false)
      }
      .scaleEffect(stickPressed ? stickPressScale : 1.0)
      .offset(x: stickOffset.width, y: stickOffset.height + stickPressYOffset)
      .animation(stickPressAnimation, value: stickPressed)
    }
    .frame(width: size, height: size)
    // Allow tap regions to exceed the circular art (within the view's square bounds).
    .contentShape(Rectangle())
    .overlay {
      if DebugBuild.isEnabled && debugShowTapRegions {
        tapRegionDebugOverlay(size: size)
      }
    }
    .modifier(platformDPadInteraction(size: size))
    .appButtonShadow(radius: 8, opacity: 0.2)
  }

  // MARK: - Drag Gesture

  private func dragGesture(size: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)  // Start immediately to capture press
      .onChanged { value in
        if !isDragging {
          isDragging = true
          isPressingOK = isStartInOKRegion(startLocation: value.startLocation, size: size)
        }
        dragOffset = value.translation

        let distance = hypot(value.translation.width, value.translation.height)
        // Once we leave the OK dead zone, treat it as "drag mode" for visuals and keep it latched.
        if !isInDragMode, distance >= okDeadZone {
          isInDragMode = true
        }

        // If we're still within the OK dead zone, treat it as a tap/hold.
        // - Tap (<0.5s) fires once on release (existing behavior).
        // - Hold (>=0.5s) starts repeating with a time-based ramp.
        if distance < okDeadZone {
          let tapDir = detectTapDirection(startLocation: value.startLocation, size: size)
          updateTapHoldRepeat(direction: tapDir, size: size)
          return
        } else {
          // Transitioning to drag mode cancels any tap-hold repeat.
          stopTapHoldRepeat()
        }

        let direction = detectDirection(from: value.translation)

        if direction != currentDirection {
          // Direction changed (or entered/exited dead zone)
          stopRepeat()
          Log.debug(
            "DPad",
            "Direction changed: \(String(describing: currentDirection)) → \(String(describing: direction)), distance=\(Int(distance))"
          )
          currentDirection = direction

          if let dir = direction, distance >= activationThreshold {
            // Valid direction detected
            Log.debug("DPad", "🎯 FIRE: \(dir), distance=\(Int(distance))")
            HapticService.play(.click)
            onDirection(dir)
            hasFiredDirection = true
            startRepeat(distance: distance, size: size)
          }
        } else if currentDirection != nil, distance >= activationThreshold {
          // Same direction, update repeat rate based on distance
          updateRepeatRate(distance: distance, size: size)
        }
      }
      .onEnded { value in
        let distance = hypot(value.translation.width, value.translation.height)

        // Tap behavior: if user didn't really drag, decide between arrow-tap vs OK-tap
        // using the initial touch location (relative to the DPad center).
        if distance < okDeadZone && !hasFiredDirection {
          let tapDir = detectTapDirection(
            startLocation: value.startLocation,
            size: size
          )
          HapticService.play(.click)
          if let tapDir {
            onDirection(tapDir)
          } else if isStartInOKRegion(startLocation: value.startLocation, size: size) {
            onOK()
          }
        }

        // Reset state
        isDragging = false
        isInDragMode = false
        isPressingOK = false
        dragOffset = .zero
        stopTapHoldRepeat()
        stopRepeat()
        currentDirection = nil
        hasFiredDirection = false
      }
  }

  // MARK: - Tap-hold repeat (arrow regions)

  private func updateTapHoldRepeat(direction: RemoteAction?, size: CGFloat) {
    // Only arrow directions repeat on hold. (OK remains a tap-only action.)
    guard let dir = direction else {
      stopTapHoldRepeat()
      return
    }

    if tapHoldDirection != dir {
      stopTapHoldRepeat()
      tapHoldDirection = dir
      tapHoldStartedAt = Date()
      scheduleNextTapHoldTick(size: size)
    } else if tapHoldTimer == nil {
      // Defensive: if timer got cancelled, restart.
      if tapHoldStartedAt == nil { tapHoldStartedAt = Date() }
      scheduleNextTapHoldTick(size: size)
    }
  }

  private func stopTapHoldRepeat() {
    tapHoldTimer?.invalidate()
    tapHoldTimer = nil
    tapHoldStartedAt = nil
    tapHoldDirection = nil
  }

  private func scheduleNextTapHoldTick(size: CGFloat) {
    tapHoldTimer?.invalidate()
    guard let startedAt = tapHoldStartedAt, tapHoldDirection != nil else { return }

    let now = Date()
    let elapsed = now.timeIntervalSince(startedAt)
    let firstRepeatDelay: TimeInterval = 0.5

    // First click starts at t=0.5s. Before that, do nothing; quick taps fire on release.
    let fireIn: TimeInterval = max(0, firstRepeatDelay - elapsed)

    tapHoldTimer = Timer.scheduledTimer(withTimeInterval: fireIn, repeats: false) { _ in
      guard isDragging else { return }
      guard let dir2 = tapHoldDirection else { return }

      // Fire one repeat tick.
      HapticService.play(.click)
      onDirection(dir2)
      hasFiredDirection = true

      // Schedule next tick using time-based ramp, clamped at t=2.0s.
      let elapsed2 = Date().timeIntervalSince(startedAt)
      let interval = holdRepeatInterval(elapsed: elapsed2, size: size)
      tapHoldTimer?.invalidate()
      tapHoldTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
        scheduleNextTapHoldTick(size: size)
      }
    }
  }

  private func holdRepeatInterval(elapsed: TimeInterval, size: CGFloat) -> TimeInterval {
    // Same curve as drag-repeat, but driven by time since press.
    // - Clamp ramp at t=2.0s
    // - First click begins at t=0.5s (so ramp time window is 1.5s)
    let t0: TimeInterval = 0.5
    let t1: TimeInterval = 2.0
    let u: CGFloat = {
      if elapsed <= t0 { return 0 }
      if elapsed >= t1 { return 1 }
      return CGFloat((elapsed - t0) / (t1 - t0))
    }()

    return repeatInterval(forNormalized: u)
  }

  // MARK: - Direction Detection with Angular Dead Zones

  private func detectDirection(from translation: CGSize) -> RemoteAction? {
    let distance = hypot(translation.width, translation.height)
    guard distance >= activationThreshold else { return nil }

    // Calculate angle in degrees (-180 to 180)
    // atan2 returns: right=0, down=90, left=±180, up=-90
    let angleRadians = atan2(translation.height, translation.width)
    let angleDegrees = angleRadians * 180 / .pi

    // Check if within ±angularTolerance of each cardinal direction
    // Right: 0°
    if abs(angleDegrees) <= angularTolerance {
      return .right
    }

    // Down: 90°
    if abs(angleDegrees - 90) <= angularTolerance {
      return .down
    }

    // Up: -90°
    if abs(angleDegrees + 90) <= angularTolerance {
      return .up
    }

    // Left: ±180°
    if abs(angleDegrees) >= (180 - angularTolerance) {
      return .left
    }

    // In diagonal dead zone
    return nil
  }

  /// Visual-only direction gating: uses the same angular dead zones, but a smaller minimum distance
  /// so the stick can start moving as soon as the user leaves the OK dead zone.
  private func detectDirectionForVisual(from translation: CGSize) -> RemoteAction? {
    let distance = hypot(translation.width, translation.height)
    guard distance >= okDeadZone else { return nil }

    let angleRadians = atan2(translation.height, translation.width)
    let angleDegrees = angleRadians * 180 / .pi

    if abs(angleDegrees) <= angularTolerance { return .right }
    if abs(angleDegrees - 90) <= angularTolerance { return .down }
    if abs(angleDegrees + 90) <= angularTolerance { return .up }
    if abs(angleDegrees) >= (180 - angularTolerance) { return .left }
    return nil
  }

  // MARK: - Auto-Repeat

  private func startRepeat(distance: CGFloat, size: CGFloat) {
    let interval = repeatInterval(for: distance, size: size)
    guard interval > 0 else { return }

    Log.debug("DPad", "Repeat timer started: \(interval)s")
    repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
      if let dir = currentDirection {
        Log.debug("DPad", "🔁 REPEAT: \(dir)")
        HapticService.play(.click)
        onDirection(dir)
      }
    }
  }

  private func updateRepeatRate(distance: CGFloat, size: CGFloat) {
    let newInterval = repeatInterval(for: distance, size: size)

    // Only update if significantly different
    if let timer = repeatTimer, timer.isValid {
      let currentInterval = timer.timeInterval
      if abs(newInterval - currentInterval) > 0.05 {
        stopRepeat()
        if newInterval > 0 {
          startRepeat(distance: distance, size: size)
        }
      }
    } else if newInterval > 0 {
      startRepeat(distance: distance, size: size)
    }
  }

  private func repeatInterval(for distance: CGFloat, size: CGFloat) -> TimeInterval {
    // Non-linear ramp: slow in the first half of the drag range, faster in the second half.
    // We treat max drag distance as 2R (where R is DPad radius), so max ~= size.
    // (Distance here is based on drag translation, which can exceed the view bounds.)
    let minDistanceForRepeat: CGFloat = 18
    if distance < minDistanceForRepeat { return 0 }

    // 0..1 over 0..(2R)
    let maxDragDistance: CGFloat = max(1, size)
    let u = max(0, min(1, distance / maxDragDistance))

    return repeatInterval(forNormalized: u)
  }

  private func repeatInterval(forNormalized u: CGFloat) -> TimeInterval {
    let u01 = max(0, min(1, u))

    // Piecewise quadratic:
    // - Slow ramp occupies more of the range (0..2/3)
    // - Faster ramp in the final third (2/3..1)
    let t: CGFloat
    let b: CGFloat = 2.0 / 3.0
    if u01 <= b {
      // Map 0..b → 0..0.5 (quadratic)
      let x = u01 / max(0.0001, b)
      t = 0.5 * (x * x)
    } else {
      // Map b..1 → 0.5..1 (quadratic)
      let denom = max(0.0001, (1.0 - b))
      let x = (u01 - b) / denom
      t = 0.5 + 0.5 * (x * x)
    }

    // Map curve to interval (seconds). Tune these two endpoints for overall feel.
    let slow: CGFloat = 0.33  // ~3/sec
    let fast: CGFloat = 0.12  // ~8/sec (slightly less aggressive than 0.125)
    let interval = slow + (fast - slow) * t
    return TimeInterval(max(0.08, min(0.5, interval)))
  }

  private func stopRepeat() {
    repeatTimer?.invalidate()
    repeatTimer = nil
  }

  // MARK: - Visual Feedback

  private func stickOffsetForVisual(size: CGFloat) -> CGSize {
    guard isDragging else { return .zero }

    let distance = hypot(dragOffset.width, dragOffset.height)
    guard distance >= okDeadZone else { return .zero }

    // Only allow motion along a cardinal axis if the drag is within angularTolerance degrees.
    guard let dir = detectDirectionForVisual(from: dragOffset) else { return .zero }

    // Treat physical drag range as 0..(2R) == 0..size, then move stick at half.
    let maxDragAxis: CGFloat = size
    let maxVisualAxis: CGFloat = size * stickMaxVisualTravelFractionOfSize

    func clampAxis(_ v: CGFloat) -> CGFloat {
      let raw = max(-maxDragAxis, min(maxDragAxis, v))
      let visual = raw * stickVisualMovementScale
      return max(-maxVisualAxis, min(maxVisualAxis, visual))
    }

    switch dir {
    case .left, .right:
      return CGSize(width: clampAxis(dragOffset.width), height: 0)
    case .up, .down:
      return CGSize(width: 0, height: clampAxis(dragOffset.height))
    default:
      return .zero
    }
  }

  private func detectTapDirection(startLocation: CGPoint, size: CGFloat) -> RemoteAction? {
    let s = tapShapes(size: size)
    if s.up.contains(startLocation) { return .up }
    if s.down.contains(startLocation) { return .down }
    if s.left.contains(startLocation) { return .left }
    if s.right.contains(startLocation) { return .right }
    return nil
  }

  private func isStartInOKRegion(startLocation: CGPoint, size: CGFloat) -> Bool {
    tapShapes(size: size).ok.contains(startLocation)
  }

  private func tapShapes(size: CGFloat) -> (up: Path, down: Path, left: Path, right: Path, ok: Path)
  {
    let center = CGPoint(x: size / 2, y: size / 2)
    let inner = size * arrowTapInnerRadiusFractionOfSize
    let outer = size * arrowTapOuterRadiusFractionOfSize
    let baseHalf = size * arrowTapAxisHalfWidthFractionOfSize

    // Reuse the same art-driven centerline adjustment as the stick + shadow clip.
    let cy =
      center.y
      + (size * stickShadowClipMidpointYOffsetFractionOfSize
        * tapCenterlineMultiplierOfShadowMidpoint)

    let reachRadians = Double(arrowTapReachAngleDegrees) * Double.pi / 180.0
    let slope = CGFloat(tan(reachRadians))
    let axial = max(0, outer - inner)
    let outerHalf = max(0, baseHalf + slope * axial)

    func trapezoid(_ pts: [CGPoint]) -> Path {
      var p = Path()
      guard let first = pts.first else { return p }
      p.move(to: first)
      for pt in pts.dropFirst() { p.addLine(to: pt) }
      p.closeSubpath()
      return p
    }

    let up = trapezoid([
      CGPoint(x: center.x - outerHalf, y: cy - outer),
      CGPoint(x: center.x + outerHalf, y: cy - outer),
      CGPoint(x: center.x + baseHalf, y: cy - inner),
      CGPoint(x: center.x - baseHalf, y: cy - inner),
    ])

    let down = trapezoid([
      CGPoint(x: center.x - baseHalf, y: cy + inner),
      CGPoint(x: center.x + baseHalf, y: cy + inner),
      CGPoint(x: center.x + outerHalf, y: cy + outer),
      CGPoint(x: center.x - outerHalf, y: cy + outer),
    ])

    let left = trapezoid([
      CGPoint(x: center.x - outer, y: cy - outerHalf),
      CGPoint(x: center.x - inner, y: cy - baseHalf),
      CGPoint(x: center.x - inner, y: cy + baseHalf),
      CGPoint(x: center.x - outer, y: cy + outerHalf),
    ])

    let right = trapezoid([
      CGPoint(x: center.x + inner, y: cy - baseHalf),
      CGPoint(x: center.x + outer, y: cy - outerHalf),
      CGPoint(x: center.x + outer, y: cy + outerHalf),
      CGPoint(x: center.x + inner, y: cy + baseHalf),
    ])

    // For visualization only (OK is selected when none of the arrow shapes match).
    let ok = Path(
      ellipseIn: CGRect(x: center.x - inner, y: cy - inner, width: inner * 2, height: inner * 2)
    )
    return (up, down, left, right, ok)
  }

  private func tapRegionDebugOverlay(size: CGFloat) -> some View {
    let s = tapShapes(size: size)
    return ZStack {
      s.up.stroke(Color.red.opacity(0.9), lineWidth: 2)
      s.down.stroke(Color.red.opacity(0.9), lineWidth: 2)
      s.left.stroke(Color.red.opacity(0.9), lineWidth: 2)
      s.right.stroke(Color.red.opacity(0.9), lineWidth: 2)
      s.ok.stroke(Color.red.opacity(0.45), lineWidth: 1)
    }
    .allowsHitTesting(false)
  }

  private func shadowOffsetForVisual(stickOffset: CGSize) -> CGSize {
    return CGSize(
      width: stickOffset.width,
      height: stickOffset.height * shadowVerticalRate
    )
  }

  private func shadowClipMask(size: CGFloat, stickOffset: CGSize, midpointYOffset: CGFloat)
    -> some View
  {
    GeometryReader { geo in
      // Convert the stick midpoint (in center-based coords) into a top-based cutoff line.
      let cutoffFromTop = (geo.size.height / 2) + stickOffset.height + midpointYOffset
      let cutoff = max(0, min(geo.size.height, cutoffFromTop))

      Rectangle()
        .frame(width: geo.size.width, height: max(0, geo.size.height - cutoff))
        .offset(x: 0, y: cutoff)
    }
    .frame(width: size, height: size)
  }

  private func dpadLayer(named name: String, size: CGFloat) -> some View {
    // Prefer explicit bundle file lookup so we don't depend on Asset Catalog behavior.
    if let path = Bundle.main.path(forResource: name, ofType: "png"),
      let image = PlatformSwiftUIImage.contentsOfFile(path)
    {
      return AnyView(
        image
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
      )
    }

    // Debug fallback: if an image can't be found, show something visible and log.
    DebugBuild.run {
      Log.warn(
        "DPad",
        "Missing DPad image resource: \(name).png (bundle=\(Bundle.main.bundleIdentifier ?? "nil"))"
      )
    }

    return AnyView(
      Circle()
        .fill(Color.red.opacity(0.18))
        .overlay(Circle().stroke(Color.red.opacity(0.9), lineWidth: 1))
        .frame(width: size, height: size)
        .overlay(
          Text("Missing\n\(name)")
            .font(.system(size: max(10, size * 0.09), weight: .semibold))
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        )
    )
  }
}

// MARK: - Platform interaction (implementation detail)
//
// Intent: keep `DPadView`'s core interaction logic readable by pushing watch-vs-nonWatch routing
// to one place at the bottom of the file.
extension DPadView {
  /// Platform routing hook used by the main view modifier chain.
  ///
  /// Implemented in the single `#if os(watchOS)` block below so the main DPad code stays clean.
  fileprivate func platformDPadInteraction(size: CGFloat) -> some ViewModifier {
    PlatformDPadInteraction(dPad: self, size: size)
  }
}

#if os(watchOS)
  extension DPadView {
    fileprivate struct PlatformDPadInteraction: ViewModifier {
      let dPad: DPadView
      let size: CGFloat

      func body(content: Content) -> some View {
        content.overlay { dPad.watchInteractionOverlay(size: size) }
      }
    }

    // MARK: - watchOS interaction routing
    //
    // Goal: don't claim swipes that should page-switch.
    // - Arrow regions are tap-only (no drag gesture attached there).
    // - Only the center OK region owns the drag gesture.

    fileprivate struct FrozenPathShape: Shape {
      let path: Path
      func path(in rect: CGRect) -> Path { path }
    }

    @ViewBuilder
    fileprivate func watchInteractionOverlay(size: CGFloat) -> some View {
      let shapes = tapShapes(size: size)
      let okDiameter = (size * arrowTapInnerRadiusFractionOfSize) * 2

      ZStack {
        watchArrowTapRegion(shape: FrozenPathShape(path: shapes.up), direction: .up)
        watchArrowTapRegion(shape: FrozenPathShape(path: shapes.down), direction: .down)
        watchArrowTapRegion(shape: FrozenPathShape(path: shapes.left), direction: .left)
        watchArrowTapRegion(shape: FrozenPathShape(path: shapes.right), direction: .right)

        Color.clear
          .frame(width: okDiameter, height: okDiameter)
          .contentShape(Circle())
          // Reuse the same drag gesture implementation, but *only* attach it to the OK region.
          // This avoids duplicating drag/repeat logic and prevents the DPad from stealing page-swipes.
          .gesture(dragGesture(size: size))
      }
      .frame(width: size, height: size)
    }

    fileprivate func watchArrowTapRegion<S: Shape>(shape: S, direction: RemoteAction) -> some View {
      Color.clear
        .contentShape(shape)
        .onTapGesture {
          DebugBuild.run {
            Log.debug("DPad", "watchOS arrow tap: \(direction)")
          }
          HapticService.play(.click)
          onDirection(direction)
        }
    }
  }
#else
  extension DPadView {
    fileprivate struct PlatformDPadInteraction: ViewModifier {
      let dPad: DPadView
      let size: CGFloat

      func body(content: Content) -> some View {
        content.gesture(dPad.dragGesture(size: size))
    }
  }
}
#endif

#Preview("Watch (80) @2x (top)") {
  VStack(spacing: 0) {
    DPadView(
      onDirection: { dir in Log.debug("DPad", "Direction: \(dir)") },
      onOK: { Log.debug("DPad", "OK pressed") },
      size: 80
    )
    .frame(width: 80, height: 80)
    .scaleEffect(2.0, anchor: .top)

    Spacer(minLength: 0)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  .background(Color.black)
}

#Preview("Phone (150) @2x (top)") {
  VStack(spacing: 0) {
    DPadView(
      onDirection: { dir in Log.debug("DPad", "Direction: \(dir)") },
      onOK: { Log.debug("DPad", "OK pressed") },
      size: 150
    )
    .frame(width: 150, height: 150)
    .scaleEffect(2.0, anchor: .top)

    Spacer(minLength: 0)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  .background(Color.black)
}
