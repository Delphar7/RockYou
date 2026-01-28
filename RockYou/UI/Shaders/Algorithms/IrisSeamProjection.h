// IrisSeamProjection.h
// RockYou
//
// Unified projection functions for iris seam geometry.
// Both point2seam and seam2point use the same math, ensuring consistency.
//
// Coordinate spaces:
// - Dome space: 3D hemisphere, Y up, radius R
// - Disc space: 2D projection (x, z), un-twisted
// - Twisted space: 2D with spiral twist applied
// - Iris space: Twisted space scaled to iris radius
//
// The twist is a function of radial distance: theta = asin(r / R)

#pragma once

#include <metal_stdlib>

using namespace metal;

namespace iris_projection {

// =============================================================================
// Core projection functions
// =============================================================================

/// Compute twist angle from radial distance in dome space
/// theta = polar angle from Y axis = asin(r_xz / R)
/// twistAngle = theta / (π/2) * twistRadians
inline float computeTwistAngle(float radialDist, float domeRadius, float twistRadians) {
  float sinTheta = clamp(radialDist / domeRadius, 0.0f, 1.0f);
  float theta = asin(sinTheta);  // 0 at apex, π/2 at equator
  float twistFraction = theta / (M_PI_F / 2.0f);
  return twistFraction * twistRadians;
}

/// Rotate a 2D point around origin by angle
inline float2 rotate2D(float2 p, float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// =============================================================================
// Point to Seam (3D dome point → seam info)
// =============================================================================

/// Transform 3D dome point to 2D iris space (for blade coverage checks)
inline float2 domePointToIrisSpace(
    float3 domePos,
    float domeRadius,
    float irisRadius,
    float twistRadians
) {
  // Project to disc (x, z)
  float2 discPos = float2(domePos.x, domePos.z);

  // Compute twist from radial distance
  float radialDist = length(discPos);
  float twistAngle = computeTwistAngle(radialDist, domeRadius, twistRadians);

  // Apply twist
  float2 twistedPos = rotate2D(discPos, twistAngle);

  // Scale to iris space
  float scale = irisRadius / domeRadius;
  return twistedPos * scale;
}

// =============================================================================
// Seam to Point (2D iris space → 3D dome point)
// =============================================================================

/// Transform 2D iris space point to 3D dome surface
/// This is the exact inverse of domePointToIrisSpace
inline float3 irisSpaceToDomePoint(
    float2 irisPos,
    float domeRadius,
    float irisRadius,
    float twistRadians
) {
  // Scale back to twisted dome space
  float scale = domeRadius / irisRadius;
  float2 twistedPos = irisPos * scale;

  // Radial distance is preserved through twist (rotation around origin)
  float radialDist = length(twistedPos);

  // Clamp to dome boundary
  if (radialDist > domeRadius) {
    twistedPos = normalize(twistedPos) * domeRadius;
    radialDist = domeRadius;
  }

  // Compute twist angle from radial distance (same formula as forward path!)
  float twistAngle = computeTwistAngle(radialDist, domeRadius, twistRadians);

  // UN-twist (negative angle)
  float2 discPos = rotate2D(twistedPos, -twistAngle);

  // Project to 3D dome surface
  // y = sqrt(R² - x² - z²) = sqrt(R² - radialDist²) = R * cos(theta)
  float y = sqrt(max(0.0f, domeRadius * domeRadius - radialDist * radialDist));

  return float3(discPos.x, y, discPos.y);
}

// =============================================================================
// Helper: compute P_i for a blade
// =============================================================================

inline float2 computePiForBlade(
    int bladeIndex,
    float aperture,
    int bladeCount,
    float irisRadius
) {
  float pivotAngle = float(bladeIndex) * (2.0f * M_PI_F / float(max(1, bladeCount)));
  float2 pivotPos = float2(irisRadius * cos(pivotAngle), irisRadius * sin(pivotAngle));

  float closureRotation = M_PI_F / 3.0f;
  float bladeAngle = pivotAngle + aperture * closureRotation;
  float c = cos(bladeAngle);
  float s = sin(bladeAngle);
  float2 pLocal = float2(-irisRadius, 0);
  float2 pRel = float2(c * pLocal.x - s * pLocal.y, s * pLocal.x + c * pLocal.y);

  return pivotPos + pRel;
}

// =============================================================================
// Helper: circle-circle intersection (equal radii)
// =============================================================================

/// Find intersection of two circles with equal radius.
/// Returns the intersection point closer to origin (aperture side).
inline float2 circleCircleIntersect(
    float2 center1,
    float2 center2,
    float radius
) {
  float2 midpoint = (center1 + center2) * 0.5f;
  float d = length(center2 - center1);

  // If circles don't intersect or are coincident, return midpoint
  if (d < 0.001f || d > 2.0f * radius) {
    return midpoint;
  }

  // Height from midpoint to intersection (Pythagorean)
  float h = sqrt(max(0.0f, radius * radius - d * d * 0.25f));

  // Perpendicular direction
  float2 dir = center2 - center1;
  float2 perpDir = float2(-dir.y, dir.x) / d;

  // Two intersection points
  float2 intersect1 = midpoint + perpDir * h;
  float2 intersect2 = midpoint - perpDir * h;

  // Return the one closer to origin (aperture side)
  return (length(intersect1) < length(intersect2)) ? intersect1 : intersect2;
}

// =============================================================================
// Seam curve computation
// =============================================================================

/// Compute a point along blade i's seam curve
/// arcT: 0 = aperture edge (meets successor blade), 1 = dome edge
/// Returns 3D position on dome surface, or Y=-1000 if seam should be hidden
inline float3 computeSeamPoint(
    int bladeIndex,
    float arcT,
    float aperture,      // 0 = open, 1 = closed
    int bladeCount,
    float irisRadius,
    float domeRadius,
    float twistRadians
) {
  // Hide seams when iris is nearly fully open
  if (aperture < 0.05f) {
    return float3(0, -1000.0f, 0);
  }

  // Compute P_i for this blade and its successor
  float2 pi = computePiForBlade(bladeIndex, aperture, bladeCount, irisRadius);
  int successor = (bladeIndex + 1) % bladeCount;
  float2 piNext = computePiForBlade(successor, aperture, bladeCount, irisRadius);

  // Aperture end: intersection with successor's arc (where seams meet)
  float2 aperturePoint = circleCircleIntersect(pi, piNext, irisRadius);

  // Dome end: intersection with dome boundary circle (origin, irisRadius)
  float piDist = length(pi);
  piDist = min(piDist, 2.0f * irisRadius * 0.999f);
  float halfArc = acos(clamp(piDist / (2.0f * irisRadius), 0.0f, 1.0f));
  float angleToOrigin = atan2(-pi.y, -pi.x);
  float angleToDome = angleToOrigin - halfArc;
  float2 domePoint = pi + float2(cos(angleToDome), sin(angleToDome)) * irisRadius;

  // Compute angles on blade i's arc for both endpoints
  float angleAperture = atan2(aperturePoint.y - pi.y, aperturePoint.x - pi.x);
  float angleDome = atan2(domePoint.y - pi.y, domePoint.x - pi.x);

  // Ensure we go the right way around the arc (shorter path typically)
  float angleDiff = angleDome - angleAperture;
  if (angleDiff > M_PI_F) angleDiff -= 2.0f * M_PI_F;
  if (angleDiff < -M_PI_F) angleDiff += 2.0f * M_PI_F;

  // Interpolate along arc from aperture (arcT=0) to dome (arcT=1)
  float arcAngle = angleAperture + arcT * angleDiff;
  float2 arcPoint = pi + float2(cos(arcAngle), sin(arcAngle)) * irisRadius;

  // Project to 3D dome surface using consistent projection
  return irisSpaceToDomePoint(arcPoint, domeRadius, irisRadius, twistRadians);
}

}  // namespace iris_projection
