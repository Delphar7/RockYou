// ConfettiAlgorithm.h
// RockYou
//
// Confetti algorithm: Fragments flutter down like confetti.
// Slower fall, more horizontal drift, sinusoidal flutter motion.

#pragma once

#include <metal_stdlib>
#include "../FragmentState.h"
#include "../FragmentMath.h"

using namespace metal;
using namespace fragment_math;

// =============================================================================
// Confetti Algorithm State
// =============================================================================

struct ConfettiFragmentState {
  float3 position;        // World position after physics
  float3 normal;          // Rotated normal
  float4 rotation;        // Current rotation quaternion
  float elapsed;          // Time since spawn
  bool visible;           // Above clip plane
};

// =============================================================================
// Confetti Algorithm Implementation
// =============================================================================

// Use shared types from FragmentMath.h
using DomeParams = fragment_math::DomeParams;
using PhysicsConfig = fragment_math::PhysicsConfig;

namespace confetti {

// Per-fragment physics data (read from texture lookup table)
// Same layout as explode, but interpreted differently
struct PhysicsData {
  float3 driftDirection;  // Horizontal drift direction
  float driftSpeed;       // Horizontal drift magnitude
  float fallSpeed;        // Vertical fall speed (slower than explode)
  float3 tumbleAxis;      // Axis for tumbling rotation
  float tumbleSpeed;      // Tumble rotation speed
  float flutterPhase;     // Phase offset for flutter
  float flutterFreq;      // Flutter frequency
  float cannonPower;      // Initial upward velocity
};

// Read cannon power from texture header (row 0, col 7, GB channels)
template<typename T>
inline float readCannonPower(
    texture2d<T, access::sample> tex,
    sampler texSampler,
    float texWidth,
    float texHeight
) {
  float2 uv = float2(7.5f / texWidth, 0.5f / texHeight);
  float4 data = float4(tex.sample(texSampler, uv));
  return decode16bit(data.g, data.b, 0.0f, 5.0f);
}

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

  // Read physics config from texture header
  PhysicsConfig config = readPhysicsConfig(tex, texSampler, texWidth, texHeight);

  // Drift direction: horizontal only (seeds 200-201)
  pd.driftDirection = normalize(float3(
    stable_random(fragmentIndex, 200, -1.0f, 1.0f),
    0,
    stable_random(fragmentIndex, 201, -1.0f, 1.0f)
  ) + float3(0.001f, 0, 0));

  // Drift speed: 0 to baseSpeed (seed 202) - confetti drifts gently
  pd.driftSpeed = stable_random(fragmentIndex, 202, 0.0f, config.baseSpeed + 0.3f);

  // Fall speed: based on gravity config (seed 203)
  pd.fallSpeed = config.baseGravity * stable_random(fragmentIndex, 203, config.gravityMin, config.gravityMax) * 0.5f;

  // Tumble axis: any direction (seeds 210-212)
  pd.tumbleAxis = normalize(float3(
    stable_random(fragmentIndex, 210, -1.0f, 1.0f),
    stable_random(fragmentIndex, 211, -1.0f, 1.0f),
    stable_random(fragmentIndex, 212, -1.0f, 1.0f)
  ) + float3(0.001f, 0.001f, 0.001f));

  // Tumble speed: use spin rate config (seed 213)
  pd.tumbleSpeed = stable_random(fragmentIndex, 213, config.spinRateMin, config.spinRateMax);

  // Flutter phase: 0 to 2π (seed 220)
  pd.flutterPhase = stable_random(fragmentIndex, 220, 0.0f, 2.0f * M_PI_F);

  // Flutter frequency: 2-6 Hz (seed 221)
  pd.flutterFreq = stable_random(fragmentIndex, 221, 2.0f, 6.0f);

  // Read cannon power from header (still from texture)
  pd.cannonPower = readCannonPower(tex, texSampler, texWidth, texHeight);

  return pd;
}

// Compute fragment state for confetti algorithm
inline ConfettiFragmentState computeState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  ConfettiFragmentState state;

  // Compute center from tessellation
  float3 center = computeCenterFromIndex(
    fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius
  );

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

  float t = state.elapsed;

  // Confetti physics: slow fall with sinusoidal flutter
  float flutter = sin(physics.flutterFreq * t + physics.flutterPhase) * 0.05f;
  float3 flutterOffset = float3(flutter, 0, flutter * 0.7f);

  // Horizontal drift
  float3 drift = physics.driftDirection * physics.driftSpeed * t;

  // Cannon: initial upward velocity, then gravity pulls down
  // y = cannonPower * t - fallSpeed * t^2
  float cannonUp = physics.cannonPower * t;
  float fall = physics.fallSpeed * t * t;

  state.position = center + drift + flutterOffset + float3(0, cannonUp - fall, 0);

  // Tumbling rotation (confetti tumbles as it falls)
  // Add per-fragment phase offset to break up synchronized rotations
  float tumblePhase = stable_random(fragmentIndex, 7919) * 2.0f * M_PI_F;
  float tumbleAngle = physics.tumbleSpeed * t + tumblePhase;
  state.rotation = quatFromAxisAngle(physics.tumbleAxis, tumbleAngle);
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
  ConfettiFragmentState full = computeState(fragmentIndex, time, dome, physics);
  FragmentState fs;
  fs.position = full.position;
  fs.normal = full.normal;
  fs.visible = full.visible;
  return fs;
}

}  // namespace confetti
