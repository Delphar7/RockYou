// FragmentMath.h
// RockYou
//
// Shared math utilities for all dome collapse algorithms.
// Includes quaternion operations, hashing, and dome geometry.
// Texture parameter reading is handled by TextureParams.h.

#pragma once

#include <metal_stdlib>
#include "TextureParams.h"

using namespace metal;

// =============================================================================
// Hashing
// =============================================================================

namespace fragment_math {

// PCG-based hash - full 32-bit output with good distribution
inline uint pcg_hash(int x, int seed) {
  uint input = uint(x + seed * 7919);
  uint state = input * 747796405u + 2891336453u;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

// Stable random: returns float in [0, 1] with full 32-bit precision (~4 billion values)
// Use different seeds to get uncorrelated random values for the same index
inline float stable_random(int index, int seed) {
  return float(pcg_hash(index, seed)) / 4294967295.0f;
}

// Stable random with bounds: returns float in [minVal, maxVal]
inline float stable_random(int index, int seed, float minVal, float maxVal) {
  float t = float(pcg_hash(index, seed)) / 4294967295.0f;
  return minVal + t * (maxVal - minVal);
}

// =============================================================================
// Quaternion operations
// =============================================================================

inline float4 quatMul(float4 q1, float4 q2) {
  return float4(
    q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
    q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
    q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
    q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
  );
}

inline float3 quatRotate(float4 q, float3 v) {
  float3 qv = float3(q.x, q.y, q.z);
  float3 uv = cross(qv, v);
  float3 uuv = cross(qv, uv);
  return v + ((uv * q.w) + uuv) * 2.0f;
}

inline float4 quatFromAxisAngle(float3 axis, float angle) {
  float halfAngle = angle * 0.5f;
  float s = sin(halfAngle);
  return float4(axis * s, cos(halfAngle));
}

// =============================================================================
// Dome geometry
// =============================================================================

// Compute triangle center from fragment index using dome tessellation math
inline float3 computeCenterFromIndex(int fragmentIndex, int latSegments, int lonSegments, float radius) {
  int lat, lon, triangleInQuad;

  if (latSegments <= 0 || lonSegments <= 0) {
    return float3(0, radius, 0);
  }

  if (fragmentIndex < lonSegments) {
    lat = 0;
    lon = fragmentIndex;
    triangleInQuad = 0;
  } else {
    int adjustedIndex = fragmentIndex - lonSegments;
    int trianglesPerBand = lonSegments * 2;
    lat = 1 + adjustedIndex / trianglesPerBand;
    int lonIndex = adjustedIndex % trianglesPerBand;
    lon = lonIndex / 2;
    triangleInQuad = lonIndex % 2;
  }

  lat = clamp(lat, 0, latSegments - 1);
  lon = clamp(lon, 0, lonSegments - 1);

  float theta1 = (float(lat) / float(latSegments)) * (M_PI_F / 2.0f);
  float theta2 = (float(lat + 1) / float(latSegments)) * (M_PI_F / 2.0f);
  float phi1 = (float(lon) / float(lonSegments)) * 2.0f * M_PI_F;
  float phi2 = (float(lon + 1) / float(lonSegments)) * 2.0f * M_PI_F;

  float st1 = sin(theta1), ct1 = cos(theta1);
  float st2 = sin(theta2), ct2 = cos(theta2);
  float sp1 = sin(phi1), cp1 = cos(phi1);
  float sp2 = sin(phi2), cp2 = cos(phi2);

  float3 p00 = float3(radius * st1 * cp1, radius * ct1, radius * st1 * sp1);
  float3 p10 = float3(radius * st2 * cp1, radius * ct2, radius * st2 * sp1);
  float3 p01 = float3(radius * st1 * cp2, radius * ct1, radius * st1 * sp2);
  float3 p11 = float3(radius * st2 * cp2, radius * ct2, radius * st2 * sp2);

  float3 center;
  if (lat == 0) {
    center = (p00 + p11 + p10) / 3.0f;
  } else if (triangleInQuad == 0) {
    center = (p00 + p11 + p10) / 3.0f;
  } else {
    center = (p00 + p01 + p11) / 3.0f;
  }

  return center;
}

// Compute spawn time based on wave propagation
inline float computeSpawnTime(float3 center, float3 waveOrigin, float waveSpeed, int waveEnabled) {
  if (waveEnabled == 0 || waveSpeed <= 0.001f) {
    return 0.0f;
  }
  return length(center - waveOrigin) / waveSpeed;
}

// =============================================================================
// Shared dome parameters (used by all algorithms)
// =============================================================================

struct DomeParams {
  float radius;
  int latSegments;
  int lonSegments;
  float waveSpeed;
  float3 waveOrigin;
  int waveEnabled;
};

// =============================================================================
// Physics config (ranges for stable_random)
// =============================================================================

struct PhysicsConfig {
  float baseGravity;
  float gravityMin;
  float gravityMax;
  float spinRateMin;
  float spinRateMax;
  float baseSpeed;
  float spreadAngle;
  float upwardBias;
};

// Read dome params from texture via TextureParamReader
inline DomeParams readDomeParams(thread const TextureParamReader& reader) {
  DomeParams p;
  p.radius      = reader.readFloat16<tex_param::RADIUS>(0.0f, 2.0f);
  p.latSegments = reader.readInt16<tex_param::LAT_SEGMENTS>();
  p.lonSegments = reader.readInt16<tex_param::LON_SEGMENTS>();
  p.waveSpeed   = reader.readFloat16<tex_param::WAVE_SPEED>(0.0f, 20.0f);
  float waveOriginX = reader.readFloat16<tex_param::WAVE_ORIGIN_X>(-2.0f, 2.0f);
  float waveOriginY = reader.readFloat16<tex_param::WAVE_ORIGIN_Y>(-2.0f, 2.0f);
  float waveOriginZ = reader.readFloat16<tex_param::WAVE_ORIGIN_Z>(-2.0f, 2.0f);
  p.waveOrigin  = float3(waveOriginX, waveOriginY, waveOriginZ);
  p.waveEnabled = reader.readInt16<tex_param::WAVE_ENABLED>();
  return p;
}

// Read physics config from texture via TextureParamReader
inline PhysicsConfig readPhysicsConfig(thread const TextureParamReader& reader) {
  PhysicsConfig c;
  c.baseGravity  = reader.readFloat16<tex_param::BASE_GRAVITY>(0.0f, 2.0f);
  c.gravityMin   = reader.readFloat16<tex_param::GRAVITY_MIN>(0.0f, 2.0f);
  c.gravityMax   = reader.readFloat16<tex_param::GRAVITY_MAX>(0.0f, 2.0f);
  c.spinRateMin  = reader.readFloat16<tex_param::SPIN_RATE_MIN>(0.0f, 20.0f);
  c.spinRateMax  = reader.readFloat16<tex_param::SPIN_RATE_MAX>(0.0f, 20.0f);
  c.baseSpeed    = reader.readFloat16<tex_param::BASE_SPEED>(-2.0f, 2.0f);
  c.spreadAngle  = reader.readFloat16<tex_param::SPREAD_ANGLE>(0.0f, 2.0f);
  c.upwardBias   = reader.readFloat16<tex_param::UPWARD_BIAS>(-2.0f, 2.0f);
  return c;
}

}  // namespace fragment_math
