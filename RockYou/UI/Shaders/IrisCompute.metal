// IrisCompute.metal
// RockYou
//
// Compute kernels that call IrisAlgorithm.h functions directly.
// Used by the debug view to get exact GPU-matching results without a Swift port.
// No RealityKit dependency — only metal_stdlib + algorithm header.

#include <metal_stdlib>
#include "Algorithms/IrisAlgorithm.h"

using namespace metal;

// Must match Swift IrisComputeParams — all 4-byte aligned, 32 bytes total
struct IrisComputeParams {
  int bladeCount;        // offset 0
  float domeRadius;      // offset 4
  float aperture;        // offset 8  (threshold)
  float tilt;            // offset 12
  float elevation;       // offset 16
  int arcPointCount;     // offset 20
  int latSteps;          // offset 24
  int lonSteps;          // offset 28
};

// Kernel 1: Compute seam arc points for all blades
// Grid: bladeCount * arcPointCount threads
// Output: float3 per thread (position on dome surface, or (0,-1000,0) if invalid)
kernel void irisComputeSeamArcs(
    constant IrisComputeParams& params [[buffer(0)]],
    device float3* output [[buffer(1)]],
    uint tid [[thread_position_in_grid]]
) {
  int totalThreads = params.bladeCount * params.arcPointCount;
  if (int(tid) >= totalThreads) return;

  int bladeIndex = int(tid) / params.arcPointCount;
  int arcIdx = int(tid) % params.arcPointCount;

  float arcT = float(arcIdx) / float(max(1, params.arcPointCount - 1));

  iris::SeamPointResult result = iris::computeSeamPointAndTangent(
    bladeIndex,
    arcT,
    params.aperture,
    params.bladeCount,
    params.domeRadius,
    params.tilt,
    params.elevation
  );

  output[tid] = result.valid ? result.position : float3(0.0f, -1000.0f, 0.0f);
}

// Diagnostic kernel: dump intermediate seam arc values per blade
// Output: 8 floats per blade:
//   [0] thetaStart, [1] thetaEnd, [2] thetaSpan,
//   [3] startPt.y, [4] endPt.y,
//   [5] equatorEntryResult (raw from findEquatorEntry, -1000 if failed),
//   [6] spanPos, [7] spanNeg
struct SeamDiagnostics {
  float thetaStart;
  float thetaEnd;
  float thetaSpan;
  float startY;
  float endY;
  float equatorEntryRaw;
  float u_y;      // basis vector u.y
  float v_y;      // basis vector v.y
  float alpha;    // r * u.y
  float beta;     // r * v.y
  float gamma;    // -center.y
  float ratio;    // gamma / mag
  float base;     // atan2(beta, alpha)
  float delta;    // acos(clamp(ratio))
  float r1;       // base + delta
  float r2;       // base - delta
};

kernel void irisSeamDiagnostics(
    constant IrisComputeParams& params [[buffer(0)]],
    device SeamDiagnostics* output [[buffer(1)]],
    uint tid [[thread_position_in_grid]]
) {
  if (int(tid) >= params.bladeCount) return;

  int bladeIndex = int(tid);
  float threshold = params.aperture;
  float radius = params.domeRadius;

  SeamDiagnostics diag = {};

  float3 ni = iris::computeBladeNormal(bladeIndex, params.bladeCount, params.tilt, params.elevation);
  iris::SeamCircle sc = iris::computeSeamCircle(ni, threshold, radius);
  if (!sc.valid) { output[tid] = diag; return; }

  // Trace the findEquatorEntry internals
  diag.u_y = sc.u.y;
  diag.v_y = sc.v.y;

  float alpha = sc.circleRadius * sc.u.y;
  float beta  = sc.circleRadius * sc.v.y;
  float gam   = -sc.center.y;
  diag.alpha = alpha;
  diag.beta  = beta;
  diag.gamma = gam;

  float mag = sqrt(alpha * alpha + beta * beta);
  float rat = (mag > 0.0001f) ? gam / mag : -9999.0f;
  diag.ratio = rat;
  diag.base  = atan2(beta, alpha);
  diag.delta = (mag > 0.0001f && abs(rat) <= 1.01f) ? acos(clamp(rat, -1.0f, 1.0f)) : -9999.0f;
  diag.r1 = diag.base + diag.delta;
  diag.r2 = diag.base - diag.delta;

  // Raw equator entry
  float eqEntry = iris::findEquatorEntry(sc);
  diag.equatorEntryRaw = eqEntry;

  float thetaStart = eqEntry;
  if (thetaStart < -999.0f) {
    thetaStart = atan2(sc.v.y, sc.u.y) + M_PI_F;
  }
  diag.thetaStart = thetaStart;

  int predecessor = (bladeIndex - 1 + params.bladeCount) % params.bladeCount;
  float3 nPrev = iris::computeBladeNormal(predecessor, params.bladeCount, params.tilt, params.elevation);
  float thetaEnd = iris::findSeamPointTheta(sc, nPrev, threshold);
  diag.thetaEnd = thetaEnd;
  if (thetaEnd < -999.0f) { output[tid] = diag; return; }

  diag.thetaSpan = -9999;

  float3 startPt = iris::seamCirclePoint(sc, thetaStart);
  float3 endPt = iris::seamCirclePoint(sc, thetaEnd);
  diag.startY = startPt.y;
  diag.endY = endPt.y;

  output[tid] = diag;
}

// Kernel 2: Compute blade ownership for dome sample points
// Grid: latSteps * lonSteps threads
// Output: int per thread (blade index, or -1 for aperture opening)
kernel void irisComputeBladeOwnership(
    constant IrisComputeParams& params [[buffer(0)]],
    device int* output [[buffer(1)]],
    uint tid [[thread_position_in_grid]]
) {
  int totalThreads = params.latSteps * params.lonSteps;
  if (int(tid) >= totalThreads) return;

  int latIdx = int(tid) / params.lonSteps;
  int lonIdx = int(tid) % params.lonSteps;

  float theta = float(latIdx) * (M_PI_2_F / float(params.latSteps));
  float phi = float(lonIdx) * (2.0f * M_PI_F / float(params.lonSteps));
  float R = params.domeRadius;
  float3 Q = R * float3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi));

  output[tid] = iris::findVisibleBlade(
    Q, params.aperture, params.bladeCount, params.tilt, params.elevation
  );
}
