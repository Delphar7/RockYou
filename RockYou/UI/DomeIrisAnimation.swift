// DomeIrisAnimation.swift
// RockYou
//
// Pure math helpers for the iris mask animation. No rendering logic.

import Foundation
import simd

struct DomeIrisConfig {
  // ------------------------------------------------------------
  // Aperture (mask) behavior (KEEP: this can stay as your current N-gon-ish hole)
  // ------------------------------------------------------------
  var baseClosed: Float = 0.02  // apothem at u=0
  var baseOpen: Float = 0.45  // apothem at u=1
  var rotMax: Float = 0.25  // radians; applied as -(1-u)*rotMax
  var cornerSharpness: Float = 24.0  // smooth-min k; higher => sharper polygon corners
  var edgeSoftness: Float = 0.005

  // ------------------------------------------------------------
  // Seams (divider lines) styling
  // ------------------------------------------------------------
  var seamWidth: Float = 0.02
  var seamSoftness: Float = 0.01

  // ------------------------------------------------------------
  // Seams: RIGID BLADE EDGE MODEL
  // The blade edge is a FIXED arc in blade-local space. The blade rotates rigidly.
  // ------------------------------------------------------------

  /// Pivot radius for each blade (in disc coordinates, 0..1). Near 0.85–0.95 reads mechanical.
  var seamPivotRadius: Float = 0.90

  /// How far the blade rotates while opening (radians). Sign controls direction.
  /// Positive here means CCW in math coords.
  /// ~1.2 rad needed for full opening with pivot at 0.9 and inner tip near 0.
  var seamBladeRotMax: Float = 1.0

  /// Additional blade rotation applied only during the retract phase (t from unlockEnd..1).
  /// This lets the blade edges keep moving as if the mechanism continues, while we still
  /// clip evaluation to the primary circle. Increase to make the dome fully disappear.
  var retractExtraBladeRotMax: Float = 1.5

  /// Inner tip of the blade edge (in blade-local X, fixed).
  /// This is where adjacent blade edges meet to form the aperture when closed.
  /// Smaller values let seams extend closer to center (pole avoidance handles r < 0.01).
  var seamEdgeInnerRadius: Float = 0.001

  /// Outer end of the blade edge (in blade-local X, fixed).
  var seamEdgeOuterRadius: Float = 1.0

  /// Allow seam evaluation to extend beyond the unit disc as we open.
  /// This helps avoid "arc lobes" getting stuck on the rim.
  var seamOuterOvershootMax: Float = 0.35

  /// Arc sagitta (bulge height at midpoint). 0 = straight line.
  /// This stays constant as the blade rotates - the edge shape never changes.
  var seamArcSagitta: Float = 0.12

  // ------------------------------------------------------------
  // Animation split
  // ------------------------------------------------------------
  var unlockEnd: Float = 0.80

  static let `default` = DomeIrisConfig()
}

enum DomeIrisAnimation {
  @inlinable static func clamp<T>(_ x: T) -> T where T: Numeric & Comparable { min(1, max(0, x)) }

  static func smoothstep01(_ t: Float) -> Float {
    let x = clamp(t)
    return x * x * (3 - 2 * x)
  }

  static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let denom = max(1e-6, edge1 - edge0)
    let t = clamp((x - edge0) / denom)
    return t * t * (3 - 2 * t)
  }

  /// Smooth minimum using log-sum-exp (stable enough for our [-1,1] domain).
  static func smoothMin(_ a: Float, _ b: Float, k: Float) -> Float {
    let kk = max(1e-3, k)
    let ea = exp(-kk * a)
    let eb = exp(-kk * b)
    return -log(ea + eb) / kk
  }

  // ------------------------------------------------------------
  // Geometry helpers (Metal-friendly)
  // ------------------------------------------------------------

  @inline(__always)
  static func rotate(_ p: SIMD2<Float>, _ angle: Float) -> SIMD2<Float> {
    let c = cos(angle)
    let s = sin(angle)
    return SIMD2<Float>(c * p.x - s * p.y, s * p.x + c * p.y)
  }

  @inline(__always)
  static func rotateAround(_ p: SIMD2<Float>, center: SIMD2<Float>, angle: Float) -> SIMD2<Float> {
    rotate(p - center, angle) + center
  }

  @inline(__always)
  static func wrapAnglePi(_ a: Float) -> Float {
    // Wrap to (-π, π]
    var x = a
    let twoPi = 2 * Float.pi
    x = fmod(x + Float.pi, twoPi)
    if x < 0 { x += twoPi }
    return x - Float.pi
  }

  @inline(__always)
  static func edgeYExtended(qx: Float, rInner: Float, rOuterEff: Float, sagitta: Float) -> Float {
    let denom = max(1e-6, rOuterEff - rInner)
    let t = (qx - rInner) / denom  // NOTE: not clamped on the high end

    if t <= 1 {
      let tc = max(0, t)
      return sagitta * sin(tc * .pi)
    } else {
      // Linear continuation past t=1 using tangent at the endpoint.
      let slope = -sagitta * .pi
      return slope * (t - 1)
    }
  }

  // ------------------------------------------------------------
  // Shared evaluation (single source of truth)
  // ------------------------------------------------------------

  struct IrisFrame {
    let uOpen: Float
    let uRetract: Float
    let N: Int
    let rot: Float
    let deltaOpen: Float
    let deltaRetract: Float
    let delta: Float
    let rp: Float
    let rInner: Float
    let rOuter: Float
    let rOuterEff: Float
    let sagitta: Float
    let pivotLocal: SIMD2<Float>
    let poutOpenLocal: SIMD2<Float>
    let phiSpan: Float
    let sector: Float
    let miterAngle: Float
    let miterPush: Float
  }

  @inline(__always)
  static func makeFrame(t: Float, bladeCount: Int, config: DomeIrisConfig) -> IrisFrame {
    let uOpen = smoothstep01(tUnlock(t, unlockEnd: config.unlockEnd))
    let uRetract = smoothstep01(tRetract(t, unlockEnd: config.unlockEnd))

    let N = max(3, bladeCount)
    let rp = clamp(config.seamPivotRadius)
    let rInner = config.seamEdgeInnerRadius
    let rOuter = config.seamEdgeOuterRadius
    let rOuterEff = rOuter
    let sagitta = config.seamArcSagitta

    let rot = -config.rotMax * (1 - uOpen)
    let deltaOpen = config.seamBladeRotMax * uOpen
    let deltaRetract = config.retractExtraBladeRotMax * uRetract
    let delta = deltaOpen + deltaRetract

    let pivotLocal = SIMD2<Float>(rp, 0)

    // Pout/Pin positions in blade-local space at end-of-open (opening rotation only).
    let poutOpenLocal = rotateAround(SIMD2<Float>(rOuter, 0), center: pivotLocal, angle: deltaOpen)
    let pinOpenLocal = rotateAround(SIMD2<Float>(rInner, 0), center: pivotLocal, angle: deltaOpen)

    // Hinge target: make (origin, Pout, Pin) colinear at the end of retract.
    // In blade-local space, origin is (0,0), so target direction from Pout points toward -Pout.
    let v0 = pinOpenLocal - poutOpenLocal
    let vTarget = -poutOpenLocal
    let a0 = atan2(v0.y, v0.x)
    let aT = atan2(vTarget.y, vTarget.x)
    let phiSpan = wrapAnglePi(aT - a0)

    let sector = (2 * Float.pi) / Float(N)

    let baseMiterAngle = Float.pi / Float(N) * 1.33
    let miterAngle = baseMiterAngle + (Float.pi / 2 - baseMiterAngle) * uOpen
    let miterPush: Float = 0.015 * (1 - uOpen)

    return IrisFrame(
      uOpen: uOpen,
      uRetract: uRetract,
      N: N,
      rot: rot,
      deltaOpen: deltaOpen,
      deltaRetract: deltaRetract,
      delta: delta,
      rp: rp,
      rInner: rInner,
      rOuter: rOuter,
      rOuterEff: rOuterEff,
      sagitta: sagitta,
      pivotLocal: pivotLocal,
      poutOpenLocal: poutOpenLocal,
      phiSpan: phiSpan,
      sector: sector,
      miterAngle: miterAngle,
      miterPush: miterPush
    )
  }

  struct BladeEval {
    /// Signed distance to the aperture boundary for this blade. Positive = aperture side.
    let signedDist: Float
    /// Absolute distance to the blade edge curve (for seam banding).
    let edgeDist: Float
    /// Whether this point is within the blade's mitered inner gate.
    let passedInnerGate: Bool
    /// Whether this point is within the blade's outer evaluation range.
    let passedOuterGate: Bool
  }

  @inline(__always)
  static func evalBlade(p: SIMD2<Float>, bladeIndex i: Int, frame f: IrisFrame) -> BladeEval {
    // Apply global aperture rotation to blade placement.
    let alpha = f.sector * Float(i) + f.rot

    // 1) rotate world point into blade-i base frame
    var q = rotate(p, -alpha)

    // 2) During retract, undo the hinge rotation about the pinned outer endpoint (end-of-open Pout).
    if f.uRetract > 0 {
      let phi = f.phiSpan * f.uRetract
      q = rotateAround(q, center: f.poutOpenLocal, angle: phi)
    }

    // 3) Undo opening motion by rotating the sample point around the pivot (inverse transform)
    q = rotateAround(q, center: f.pivotLocal, angle: -f.deltaOpen)

    // 4) Gate by outer radius
    let passedOuter = (q.x <= f.rOuterEff)

    // 5) Compute the curved edge Y-position (shared)
    let edgeY = edgeYExtended(
      qx: q.x, rInner: f.rInner, rOuterEff: f.rOuterEff, sagitta: f.sagitta)

    // 6) Miter the inner end
    let yOffset = q.y - edgeY
    let rInnerMitered = (f.rInner - f.miterPush) - yOffset / tan(f.miterAngle)
    let passedInner = (q.x >= rInnerMitered)

    // 7) Signed distance: positive = aperture (inside), negative = blade (covered)
    let signedDist: Float
    if passedInner {
      signedDist = q.y - edgeY
    } else {
      signedDist = q.y
    }

    // 8) Distance to edge curve (for seams)
    let edgeDist = abs(q.y - edgeY)

    return BladeEval(
      signedDist: signedDist,
      edgeDist: edgeDist,
      passedInnerGate: passedInner,
      passedOuterGate: passedOuter
    )
  }

  // ------------------------------------------------------------
  // Aperture mask: derived from seam/blade edge geometry
  // ------------------------------------------------------------

  /// Main iris mask. White = open hole. Black = covered.
  /// Derived from seam geometry: aperture is the curvilinear polygon bounded by blade inner edges.
  static func mask(
    p: SIMD2<Float>,
    t: Float,
    bladeCount: Int,
    config: DomeIrisConfig
  ) -> Float {

    if simd_length(p) > 1 { return 0 }

    let frame = makeFrame(t: t, bladeCount: bladeCount, config: config)

    var minSignedDist: Float = .greatestFiniteMagnitude
    for i in 0..<frame.N {
      let e = evalBlade(p: p, bladeIndex: i, frame: frame)
      minSignedDist = min(minSignedDist, e.signedDist)
    }

    // Inset aperture slightly so it doesn't eat into seam width
    let apertureInset = config.seamWidth * 0.5
    return smoothstep(-config.edgeSoftness, config.edgeSoftness, minSignedDist - apertureInset)
  }

  // ------------------------------------------------------------
  // Seams: curved radial blade edges
  // ------------------------------------------------------------

  /// Approximate current opening boundary radius for seam clipping.
  /// Uses circumradius proxy from apothem.
  @inline(__always)
  static func openingRadiusProxy(u: Float, bladeCount: Int, config: DomeIrisConfig) -> Float {
    let n = max(3, Float(bladeCount))
    let base = config.baseClosed + (config.baseOpen - config.baseClosed) * u
    return min(1, base / cos(.pi / n))
  }

  @inline(__always)
  static func positiveMod(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r < 0 ? (r + n) : r
  }

  /// Returns the blade index whose sector centerline is closest to theta.
  /// Sector i is centered at alpha = i*(2π/N).
  @inline(__always)
  static func nearestSectorIndex(theta: Float, bladeCount: Int) -> Int {
    let N = max(3, bladeCount)
    let sector = (2 * Float.pi) / Float(N)
    // Round to nearest integer sector centerline
    let q = theta / sector
    let k = Int(round(q))
    return positiveMod(k, N)
  }

  /// Rigid blade edge seam mask evaluated at point p (disc coords).
  /// Returns 0..1 intensity for seam lines.
  /// Each blade has a FIXED curved edge shape that rotates rigidly with the blade.
  /// Blade edges extend into neighboring sectors to create shark-tooth appearance.
  /// The mask composition (seam * (1-apertureMask)) handles aperture clipping.
  static func seamMaskRigidArc(
    p: SIMD2<Float>,
    u: Float,
    bladeCount: Int,
    config: DomeIrisConfig
  ) -> Float {
    guard config.seamWidth > 0 else { return 0 }
    let frame = makeFrame(t: u, bladeCount: bladeCount, config: config)

    // Near fully-open, multiple blades can overlap slightly at the rim.
    // Restrict to the owning sector (plus immediate neighbors) only near the end,
    // so the mid-range "shark tooth" look is preserved.
    let restrictOwnership = (frame.uOpen > 0.92)
    let theta = atan2(p.y, p.x)
    // Remove global rotation so sector ownership matches alpha = i*sector + rot
    let thetaLocal = wrapAnglePi(theta - frame.rot)
    let iCenter = nearestSectorIndex(theta: thetaLocal, bladeCount: frame.N)

    var seam: Float = 0

    func evalBladeIndex(_ i: Int) {
      let e = DomeIrisAnimation.evalBlade(p: p, bladeIndex: i, frame: frame)
      guard e.passedOuterGate else { return }
      guard e.passedInnerGate else { return }

      let s = 1 - smoothstep(config.seamWidth, config.seamWidth + config.seamSoftness, e.edgeDist)
      seam = max(seam, s)
    }

    if restrictOwnership {
      // Evaluate owning sector and immediate neighbors to avoid pops on boundaries.
      evalBladeIndex(positiveMod(iCenter - 1, frame.N))
      evalBladeIndex(iCenter)
      evalBladeIndex(positiveMod(iCenter + 1, frame.N))
    } else {
      for i in 0..<frame.N { evalBladeIndex(i) }
    }

    return seam
  }

  /// Backwards-compatible seamMask signature.
  /// Your renderer currently passes (theta, r). We rebuild p and call the rigid model.
  static func seamMask(
    theta: Float,
    r: Float,
    u: Float,
    bladeCount: Int,
    config: DomeIrisConfig
  ) -> Float {
    let p = SIMD2<Float>(r * cos(theta), r * sin(theta))
    return seamMaskRigidArc(p: p, u: u, bladeCount: bladeCount, config: config)
  }

  // ------------------------------------------------------------
  // Animation split helpers
  // ------------------------------------------------------------

  static func tUnlock(_ t: Float, unlockEnd: Float) -> Float {
    clamp(t / max(1e-6, unlockEnd))
  }

  static func tRetract(_ t: Float, unlockEnd: Float) -> Float {
    let denom = max(1e-6, 1 - unlockEnd)
    return clamp((t - unlockEnd) / denom)
  }
}
