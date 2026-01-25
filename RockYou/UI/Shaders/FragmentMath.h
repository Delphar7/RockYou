// FragmentMath.h
// RockYou
//
// Shared math utilities for all dome collapse algorithms.
// Includes quaternion operations, texture decoding, and hashing.

#pragma once

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Algorithm IDs - must match Swift DomeCollapseAlgorithm enum
// =============================================================================

constant int ALGORITHM_EXPLODE = 0;
constant int ALGORITHM_CONFETTI = 1;
constant int ALGORITHM_RIPPLE = 2;
// Future: ALGORITHM_DRAIN = 3, ALGORITHM_IRIS = 4

// =============================================================================
// Texture decoding (for RealityKit texture sampler)
// =============================================================================

namespace fragment_math {

inline float decode16bit(float highByte, float lowByte, float minVal, float maxVal) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  float val16 = float(high * 256 + low);
  return val16 / 65535.0f * (maxVal - minVal) + minVal;
}

inline int decode16bitInt(float highByte, float lowByte) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  return high * 256 + low;
}

// =============================================================================
// Hashing
// =============================================================================

// PCG-based hash - full 32-bit output with good distribution
inline uint pcg_hash(int x, int seed) {
  uint input = uint(x + seed * 7919);
  uint state = input * 747796405u + 2891336453u;
  uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
  return (word >> 22u) ^ word;
}

// Hash index for lookup table - constrained to [0, 4096) for texture rows
inline int hashIndex(int x, int seed) {
  return int(pcg_hash(x, seed) % 4096u);
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

// Read dome params from texture header (row 0, cols 3-6)
template<typename T>
inline DomeParams readDomeParams(
    texture2d<T, access::sample> tex,
    sampler texSampler,
    float texWidth,
    float texHeight
) {
  DomeParams p;

  float2 h3UV = float2(3.5f / texWidth, 0.5f / texHeight);
  float4 h3 = float4(tex.sample(texSampler, h3UV));
  p.radius = decode16bit(h3.r, h3.g, 0.0f, 2.0f);
  p.latSegments = decode16bitInt(h3.b, h3.a);

  float2 h4UV = float2(4.5f / texWidth, 0.5f / texHeight);
  float4 h4 = float4(tex.sample(texSampler, h4UV));
  p.lonSegments = decode16bitInt(h4.r, h4.g);
  p.waveSpeed = decode16bit(h4.b, h4.a, 0.0f, 20.0f);

  float2 h5UV = float2(5.5f / texWidth, 0.5f / texHeight);
  float4 h5 = float4(tex.sample(texSampler, h5UV));
  float waveOriginX = decode16bit(h5.r, h5.g, -2.0f, 2.0f);
  float waveOriginY = decode16bit(h5.b, h5.a, -2.0f, 2.0f);

  float2 h6UV = float2(6.5f / texWidth, 0.5f / texHeight);
  float4 h6 = float4(tex.sample(texSampler, h6UV));
  float waveOriginZ = decode16bit(h6.r, h6.g, -2.0f, 2.0f);
  p.waveEnabled = decode16bitInt(h6.b, h6.a);

  p.waveOrigin = float3(waveOriginX, waveOriginY, waveOriginZ);
  return p;
}

// Read physics config from texture header (row 0, cols 8-9)
template<typename T>
inline PhysicsConfig readPhysicsConfig(
    texture2d<T, access::sample> tex,
    sampler texSampler,
    float texWidth,
    float texHeight
) {
  PhysicsConfig c;

  // Col 8: baseGravity (RG), gravityMin (BA)
  float2 c8UV = float2(8.5f / texWidth, 0.5f / texHeight);
  float4 c8 = float4(tex.sample(texSampler, c8UV));
  c.baseGravity = decode16bit(c8.r, c8.g, 0.0f, 2.0f);
  c.gravityMin = decode16bit(c8.b, c8.a, 0.0f, 2.0f);

  // Col 9: gravityMax (RG), spinRateMin (BA)
  float2 c9UV = float2(9.5f / texWidth, 0.5f / texHeight);
  float4 c9 = float4(tex.sample(texSampler, c9UV));
  c.gravityMax = decode16bit(c9.r, c9.g, 0.0f, 2.0f);
  c.spinRateMin = decode16bit(c9.b, c9.a, 0.0f, 20.0f);

  // Col 10: spinRateMax (RG), baseSpeed (BA)
  float2 c10UV = float2(10.5f / texWidth, 0.5f / texHeight);
  float4 c10 = float4(tex.sample(texSampler, c10UV));
  c.spinRateMax = decode16bit(c10.r, c10.g, 0.0f, 20.0f);
  c.baseSpeed = decode16bit(c10.b, c10.a, -2.0f, 2.0f);

  // Col 11: spreadAngle (RG), upwardBias (BA)
  float2 c11UV = float2(11.5f / texWidth, 0.5f / texHeight);
  float4 c11 = float4(tex.sample(texSampler, c11UV));
  c.spreadAngle = decode16bit(c11.r, c11.g, 0.0f, 2.0f);
  c.upwardBias = decode16bit(c11.b, c11.a, -2.0f, 2.0f);

  return c;
}

}  // namespace fragment_math
