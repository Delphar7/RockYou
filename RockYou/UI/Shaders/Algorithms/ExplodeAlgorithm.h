// ExplodeAlgorithm.h
// RockYou
//
// Explode algorithm: Fragments fly outward with gravity, spinning as they fall.
// This is the original dome shatter behavior.

#pragma once

#include <metal_stdlib>
#include "../FragmentState.h"
#include "../FragmentMath.h"

using namespace metal;
using namespace fragment_math;

// =============================================================================
// Explode Algorithm State
// =============================================================================

struct ExplodeFragmentState {
  float3 position;        // World position after physics
  float3 normal;          // Rotated normal
  float4 rotation;        // Current rotation quaternion
  float elapsed;          // Time since spawn
  bool visible;           // Above clip plane
};

// =============================================================================
// Explode Algorithm Implementation
// =============================================================================

// Use shared types from FragmentMath.h
using DomeParams = fragment_math::DomeParams;
using PhysicsConfig = fragment_math::PhysicsConfig;

namespace explode {

// Per-fragment physics data (read from texture lookup table)
struct PhysicsData {
  float3 velocity;
  float gravity;
  float3 angularVelocity;
  float4 initialRotation;
  float3 center;  // Fragment center on dome (computed once, reused)
};

// Generate physics data using stable_random with configurable ranges
template<typename T>
inline PhysicsData readPhysicsData(
    int fragmentIndex,
    texture2d<T, access::sample> tex,
    sampler texSampler,
    float texWidth,
    float texHeight
) {
  PhysicsData pd;

  // Read physics config and dome params from texture header
  PhysicsConfig config = readPhysicsConfig(tex, texSampler, texWidth, texHeight);
  DomeParams dome = readDomeParams(tex, texSampler, texWidth, texHeight);

  // Compute fragment center once, store for reuse in computeState
  pd.center = computeCenterFromIndex(fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius);
  float3 outwardDir = normalize(pd.center);

  // Velocity: baseSpeed along radial direction + random spread + upward bias
  // Positive baseSpeed = explode outward, negative = implode inward
  float3 spread = float3(
    stable_random(fragmentIndex, 103, -config.spreadAngle, config.spreadAngle),
    stable_random(fragmentIndex, 104, 0.0f, config.spreadAngle),
    stable_random(fragmentIndex, 105, -config.spreadAngle, config.spreadAngle)
  );
  pd.velocity = outwardDir * config.baseSpeed + spread + float3(0, config.upwardBias, 0);

  // Gravity: baseGravity * random(gravityMin, gravityMax) (seed 106)
  pd.gravity = config.baseGravity * stable_random(fragmentIndex, 106, config.gravityMin, config.gravityMax);

  // Angular velocity: random spin axis * random(spinRateMin, spinRateMax) (seeds 110-113)
  float3 spinAxis = normalize(float3(
    stable_random(fragmentIndex, 110, -1.0f, 1.0f),
    stable_random(fragmentIndex, 111, -1.0f, 1.0f),
    stable_random(fragmentIndex, 112, -1.0f, 1.0f)
  ) + float3(0.001f, 0.001f, 0.001f));
  float spinRate = stable_random(fragmentIndex, 113, config.spinRateMin, config.spinRateMax);
  pd.angularVelocity = spinAxis * spinRate;

  // Initial rotation quaternion (seeds 120-123)
  pd.initialRotation = normalize(float4(
    stable_random(fragmentIndex, 120, -1.0f, 1.0f),
    stable_random(fragmentIndex, 121, -1.0f, 1.0f),
    stable_random(fragmentIndex, 122, -1.0f, 1.0f),
    stable_random(fragmentIndex, 123, -1.0f, 1.0f)
  ));

  return pd;
}

// Compute fragment state for explode algorithm
inline ExplodeFragmentState computeState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  ExplodeFragmentState state;

  // Use pre-computed center from physics data
  float3 center = physics.center;

  // Compute spawn time from wave
  float spawnTime = computeSpawnTime(center, dome.waveOrigin, dome.waveSpeed, dome.waveEnabled);
  state.elapsed = max(0.0f, time - spawnTime);

  // Before spawn: at original position
  if (state.elapsed <= 0.0f) {
    state.position = center;
    state.normal = normalize(center);
    state.rotation = float4(0, 0, 0, 1);
    state.visible = true;
    return state;
  }

  // Physics: position = center + velocity * t - 0.5 * gravity * t^2
  float t = state.elapsed;
  float3 offset = physics.velocity * t + float3(0, -0.5f * abs(physics.gravity) * t * t, 0);
  state.position = center + offset;

  // Rotation
  float angSpeed = length(physics.angularVelocity);
  float4 spinRotation = float4(0, 0, 0, 1);
  if (angSpeed > 0.001f) {
    float3 spinAxis = physics.angularVelocity / angSpeed;
    float spinAngle = angSpeed * t;
    spinRotation = quatFromAxisAngle(spinAxis, spinAngle);
  }
  state.rotation = normalize(quatMul(spinRotation, physics.initialRotation));
  state.normal = quatRotate(state.rotation, normalize(center));

  // Visibility
  state.visible = state.position.y >= FRAGMENT_CLIP_Y;

  return state;
}

// Convenience: compute minimal state for visibility checking only
inline FragmentState computeVisibilityState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  ExplodeFragmentState full = computeState(fragmentIndex, time, dome, physics);
  FragmentState fs;
  fs.position = full.position;
  fs.normal = full.normal;
  fs.visible = full.visible;
  return fs;
}

}  // namespace explode
