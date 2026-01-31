// IrisAlgorithm.h
// RockYou
//
// Iris mechanism: blade coverage and seam computation
// using tilted plane half-space checks instead of sphere distances.
//
// Blade i covers point Q if: dot(Q, n_i) > threshold
// where n_i = normalize(cos(tilt)*radial + sin(tilt)*tangential + tan(elevation)*up)
//
// The `tilt` parameter creates spiral seams; `elevation` lifts normals toward the apex.
// Per-fragment cost is a dot product (vs distance + sqrt for sphere model).
//
// Seam between blades is the intersection of a plane with the dome sphere,
// which is always a great or small circle on the dome surface.

#pragma once

#include <metal_stdlib>
#include "../FragmentMath.h"
#include "../FragmentState.h"

using namespace metal;

// =============================================================================
// Iris: data structures
// =============================================================================

struct IrisFragmentState {
  float3 position;
  float3 normal;
  float4 rotation;
  float elapsed;
  bool visible;
  int bladeIndex;
};

namespace iris {

using DomeParams = fragment_math::DomeParams;

// =============================================================================
// Blade normals
// =============================================================================

/// Compute blade normal for the given index.
/// Construction: cos(tilt)*radial + sin(tilt)*tangential + tan(elevation)*up, normalized.
/// tilt=0 gives radial (no spiral), tilt=π/2 gives full tangential.
/// elevation lifts the normal toward the dome apex.
inline float3 computeBladeNormal(int bladeIndex, int bladeCount, float tilt, float elevation) {
  float baseAngle = float(bladeIndex) * (2.0f * M_PI_F / float(max(1, bladeCount)));
  float3 radial     = float3(cos(baseAngle), 0.0f, sin(baseAngle));
  float3 tangential = float3(-sin(baseAngle), 0.0f, cos(baseAngle));
  float3 up         = float3(0.0f, 1.0f, 0.0f);
  float3 n = cos(tilt) * radial + sin(tilt) * tangential + tan(elevation) * up;
  return normalize(n);
}

// =============================================================================
// Blade coverage (half-space check)
// =============================================================================

/// Check if blade covers point Q: dot(Q, n_i) > threshold.
inline bool bladeCoverage(float3 Q, float3 bladeNormal, float threshold) {
  return dot(Q, bladeNormal) > threshold;
}

/// Find visible blade using pinwheel rule with dot product checks.
/// Blade i visible when it covers Q but successor does not.
/// Returns blade index or -1 if point is in the opening.
inline int findVisibleBlade(
    float3 Q,
    float threshold,
    int bladeCount,
    float tilt,
    float elevation
) {
  for (int i = 0; i < bladeCount; i++) {
    float3 ni = computeBladeNormal(i, bladeCount, tilt, elevation);
    if (dot(Q, ni) > threshold) {
      int next = (i + 1) % bladeCount;
      float3 nNext = computeBladeNormal(next, bladeCount, tilt, elevation);
      if (dot(Q, nNext) <= threshold) {
        return i;  // Blade i visible: covers Q but successor doesn't
      }
    }
  }
  return -1;  // Opening
}

// =============================================================================
// Seam geometry: plane-sphere intersection circle
// =============================================================================
//
// Boundary circle for blade i at threshold d:
//   Plane: dot(Q, n_i) = d
//   Sphere: |Q| = R
//   Center = n_i * d
//   Radius = sqrt(R² - d²)
//   Normal = n_i (general direction, not constrained to XZ)

struct SeamCircle {
  float3 center;       // Circle center (= n * threshold)
  float circleRadius;  // Radius of the intersection circle
  float3 normal;       // Circle normal (= blade normal)
  float3 u;            // Basis vector in circle plane
  float3 v;            // Basis vector in circle plane
  bool valid;          // False if threshold >= R
};

struct SeamPointResult {
  float3 position;
  float3 tangent;
  bool valid;
};

/// Compute the intersection circle of a blade's half-space plane with the dome sphere.
/// Uses general basis vectors (not constrained to XZ like sphere model).
inline SeamCircle computeSeamCircle(float3 bladeNormal, float threshold, float R) {
  SeamCircle sc;

  if (abs(threshold) >= R) {
    sc.valid = false;
    return sc;
  }

  sc.valid = true;
  sc.center = bladeNormal * threshold;
  sc.circleRadius = sqrt(max(0.0f, R * R - threshold * threshold));
  sc.normal = bladeNormal;

  // General basis vectors for arbitrary normal direction
  float3 arbitrary = abs(bladeNormal.y) < 0.9f ? float3(0.0f, 1.0f, 0.0f) : float3(1.0f, 0.0f, 0.0f);
  sc.u = normalize(cross(bladeNormal, arbitrary));
  sc.v = cross(bladeNormal, sc.u);

  return sc;
}

/// Evaluate a point on the seam circle at parameter angle theta.
inline float3 seamCirclePoint(SeamCircle sc, float theta) {
  return sc.center + sc.circleRadius * (cos(theta) * sc.u + sin(theta) * sc.v);
}

// =============================================================================
// Trig equation solver
// =============================================================================

/// Solve α*cos(θ) + β*sin(θ) = γ.
/// Returns float2(base+acos, base-acos) or (-1000, -1000) if invalid.
/// Solution: θ = atan2(β, α) ± acos(γ / √(α² + β²))
inline float2 solveTrigEquation(float alpha, float beta, float gamma) {
  float mag = sqrt(alpha * alpha + beta * beta);
  if (mag < 0.0001f) {
    return float2(-1000.0f, -1000.0f);
  }
  float ratio = gamma / mag;
  if (abs(ratio) > 1.01f) {
    return float2(-1000.0f, -1000.0f);
  }
  // Flush near-zero to +0 to avoid Metal fast-math atan2 instability:
  // atan2(y, -0.0) returns +π/2 instead of -π/2, flipping roots by π.
  float a = abs(alpha) < 1e-6f ? 0.0f : alpha;
  float b = abs(beta)  < 1e-6f ? 0.0f : beta;
  float base = atan2(b, a);
  float delta = acos(clamp(ratio, -1.0f, 1.0f));
  return float2(base + delta, base - delta);
}

// =============================================================================
// Seam arc endpoint computation
// =============================================================================
//
// The seam between blade i and blade i+1 follows blade i's boundary circle
// from the equator (Y=0) up to the seam point where blade i+1's boundary
// circle also crosses. The arc stays in the upper hemisphere.

/// Find the equator crossing theta where Y=0 and Y is increasing (entering
/// the upper hemisphere). Returns the theta value, or -1000 if no crossing.
inline float findEquatorEntry(SeamCircle sc) {
  // Y(θ) = center.y + r*(u.y*cos(θ) + v.y*sin(θ)) = 0
  float alpha = sc.circleRadius * sc.u.y;
  float beta  = sc.circleRadius * sc.v.y;
  float gamma = -sc.center.y;

  float2 roots = solveTrigEquation(alpha, beta, gamma);
  if (roots.x < -999.0f) return -1000.0f;

  // Pick the crossing where Y is increasing: dY/dθ > 0
  // dY/dθ = r*(-u.y*sin(θ) + v.y*cos(θ))
  float dY0 = sc.circleRadius * (-sc.u.y * sin(roots.x) + sc.v.y * cos(roots.x));
  return dY0 > 0 ? roots.x : roots.y;
}

/// Find the seam point theta: where blade i's boundary circle meets blade i+1's
/// half-space plane. This is the two-plane + sphere intersection point.
/// Condition: dot(P(θ), n_{i+1}) = threshold.
/// Returns the theta with Y > 0 (upper hemisphere), or -1000 if invalid.
inline float findSeamPointTheta(
    SeamCircle sc,
    float3 nextNormal,
    float threshold
) {
  // Expand dot(center + r*(cos θ * u + sin θ * v), n_next) = threshold
  // → dot(center, n_next) + r*cos θ*dot(u, n_next) + r*sin θ*dot(v, n_next) = threshold
  // Since center = n_i * threshold: dot(center, n_next) = threshold * dot(n_i, n_next)
  float alpha = sc.circleRadius * dot(sc.u, nextNormal);
  float beta  = sc.circleRadius * dot(sc.v, nextNormal);
  float gamma = threshold * (1.0f - dot(sc.normal, nextNormal));

  float2 roots = solveTrigEquation(alpha, beta, gamma);
  if (roots.x < -999.0f) return -1000.0f;

  // Pick the root in the upper hemisphere (higher Y)
  float3 p1 = seamCirclePoint(sc, roots.x);
  float3 p2 = seamCirclePoint(sc, roots.y);
  return p1.y >= p2.y ? roots.x : roots.y;
}

// =============================================================================
// Combined seam point + tangent computation
// =============================================================================

/// Compute position and analytical tangent along blade i's seam arc.
/// arcT: 0 = equator crossing (Y=0, entering upper hemisphere),
///       1 = seam point (where blade i meets blade i+1).
/// The arc follows blade i's boundary circle through the upper hemisphere.
inline SeamPointResult computeSeamPointAndTangent(
    int bladeIndex,
    float arcT,
    float threshold,
    int bladeCount,
    float radius,
    float tilt,
    float elevation
) {
  SeamPointResult result;
  result.valid = false;
  result.position = float3(0, -1000.0f, 0);
  result.tangent = float3(0, 0, 0);

  // Hide seams when threshold is near dome radius (iris nearly fully open)
  if (threshold > radius * 0.9f) {
    return result;
  }

  float3 ni = computeBladeNormal(bladeIndex, bladeCount, tilt, elevation);
  SeamCircle sc = computeSeamCircle(ni, threshold, radius);

  if (!sc.valid) {
    return result;
  }

  // Start: equator crossing where Y is increasing
  float thetaStart = findEquatorEntry(sc);
  if (thetaStart < -999.0f) {
    // Circle entirely above equator — start from the lowest Y point instead
    float thetaMinY = atan2(sc.v.y, sc.u.y) + M_PI_F;
    thetaStart = thetaMinY;
  }

  // End: seam point (where blade i's boundary meets blade i+1's plane)
  int successor = (bladeIndex + 1) % bladeCount;
  float3 nNext = computeBladeNormal(successor, bladeCount, tilt, elevation);
  float thetaEnd = findSeamPointTheta(sc, nNext, threshold);
  if (thetaEnd < -999.0f) {
    return result;
  }

  // Pick the arc direction where the Y axis (apex) is on the interior.
  // Two arcs connect equator entry to seam point; the correct one has its
  // midpoint in the upper hemisphere (concave side faces the aperture).
  float spanPos = thetaEnd - thetaStart;
  if (spanPos < 0) spanPos += 2.0f * M_PI_F;   // [0, 2π)
  float spanNeg = spanPos - 2.0f * M_PI_F;      // [-2π, 0)

  float yPos = seamCirclePoint(sc, thetaStart + spanPos * 0.5f).y;
  float yNeg = seamCirclePoint(sc, thetaStart + spanNeg * 0.5f).y;
  float thetaSpan = yPos >= yNeg ? spanPos : spanNeg;

  // Interpolate along the arc
  float theta = thetaStart + arcT * thetaSpan;

  float3 pos = seamCirclePoint(sc, theta);

  // Ensure on dome surface (numerical precision)
  float len = length(pos);
  if (len > 0.001f) {
    pos = pos * (radius / len);
  }

  // Analytical tangent: d/dt of circle parameterization
  float3 tangent = sc.circleRadius * (-sin(theta) * sc.u + cos(theta) * sc.v) * thetaSpan;

  result.position = pos;
  result.tangent = tangent;
  result.valid = true;
  return result;
}

// =============================================================================
// Config reading
// =============================================================================

struct PhysicsData {
  int bladeCount;
  float radius;
  float openDuration;
  float tilt;
  float elevation;
};

template<typename T>
inline PhysicsData readPhysicsData(
    int fragmentIndex,
    texture2d<T, access::sample> tex,
    sampler texSampler,
    float texWidth,
    float texHeight
) {
  PhysicsData pd;

  // Col 3 RG: radius
  float2 h3UV = float2(3.5f / texWidth, 0.5f / texHeight);
  float4 h3 = float4(tex.sample(texSampler, h3UV));
  pd.radius = fragment_math::decode16bit(h3.r, h3.g, 0.0f, 2.0f);

  // Col 14: bladeCount (RG), openDuration (BA)
  float2 c14UV = float2(14.5f / texWidth, 0.5f / texHeight);
  float4 c14 = float4(tex.sample(texSampler, c14UV));
  pd.bladeCount = int(fragment_math::decode16bitInt(c14.r, c14.g));
  pd.openDuration = fragment_math::decode16bit(c14.b, c14.a, 0.1f, 10.0f);

  // Col 16: tilt (RG) [0, π/2], elevation (BA) [0, π/4]
  float2 c16UV = float2(16.5f / texWidth, 0.5f / texHeight);
  float4 c16 = float4(tex.sample(texSampler, c16UV));
  pd.tilt = fragment_math::decode16bit(c16.r, c16.g, 0.0f, M_PI_2_F);
  pd.elevation = fragment_math::decode16bit(c16.b, c16.a, 0.0f, M_PI_4_F);

  return pd;
}

// =============================================================================
// Threshold computation
// =============================================================================

/// Compute the maximum threshold at which the iris is fully closed.
/// Two constraints bind:
///   - Apex (0,R,0): dot = R * sin(elevation) for all blades
///   - Equatorial midpoint (between adjacent normals): R * cos(elevation) * cos(π/N)
/// The closed threshold is the minimum of both.
inline float computeClosedThreshold(int bladeCount, float radius, float elevation) {
  float apexDot = radius * sin(elevation);
  float equatorDot = radius * cos(elevation) * cos(M_PI_F / float(max(1, bladeCount)));
  return min(apexDot, equatorDot);
}

/// Compute threshold at the given time.
/// t=0 → closed (full blade coverage), t=openDuration → open (0.95R, minimal coverage).
inline float computeThreshold(
    float time,
    float openDuration,
    int bladeCount,
    float radius,
    float elevation
) {
  float closed = computeClosedThreshold(bladeCount, radius, elevation);
  float open = radius * 0.95f;
  float progress = clamp(time / openDuration, 0.0f, 1.0f);
  return closed + progress * (open - closed);
}

// =============================================================================
// Main state computation
// =============================================================================

inline IrisFragmentState computeState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  IrisFragmentState state;
  state.elapsed = time;

  float3 center = fragment_math::computeCenterFromIndex(
    fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius
  );
  float3 normal = normalize(center);

  // t=0 → closed (closedThreshold), t=openDuration → open (0.95R)
  float threshold = computeThreshold(
    time, physics.openDuration,
    physics.bladeCount, physics.radius, physics.elevation
  );

  int bladeIndex = findVisibleBlade(
    center, threshold,
    physics.bladeCount, physics.tilt, physics.elevation
  );

  if (bladeIndex < 0) {
    state.position = float3(center.x, -1.0f, center.z);
    state.normal = normal;
    state.rotation = float4(0, 0, 0, 1);
    state.visible = false;
    state.bladeIndex = -1;
    return state;
  }

  state.position = center;
  state.normal = normal;
  state.rotation = float4(0, 0, 0, 1);
  state.visible = true;
  state.bladeIndex = bladeIndex;

  return state;
}

// =============================================================================
// Visibility state (for FRAGMENT_VISIBILITY_KERNEL macro)
// =============================================================================

inline FragmentState computeVisibilityState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  IrisFragmentState full = computeState(fragmentIndex, time, dome, physics);
  FragmentState fs;
  fs.position = full.position;
  fs.normal = full.normal;
  fs.visible = full.visible;
  return fs;
}

}  // namespace iris
