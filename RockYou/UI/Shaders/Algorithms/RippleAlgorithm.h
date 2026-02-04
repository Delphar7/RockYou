// RippleAlgorithm.h
// RockYou
//
// Ripple algorithm: Radial sin wave from origin point.
// After N waves pass over each fragment (random 2-6), it detaches and falls.
// Each fragment fades out at a random Y position (40%-120% of the way to zero).

#pragma once

#include <metal_stdlib>
#include "../FragmentState.h"
#include "../FragmentMath.h"

using namespace metal;
using namespace fragment_math;

// =============================================================================
// Ripple Algorithm State
// =============================================================================

struct RippleFragmentState {
  float3 position;        // World position after physics
  float3 normal;          // Rotated normal
  float4 rotation;        // Current rotation quaternion
  float elapsed;          // Total elapsed time
  float wavePhase;        // Normalized wave phase: 0=trough, 0.5=rest, 1=peak
  bool visible;           // Above clip plane
};

// =============================================================================
// Ripple Algorithm Implementation
// =============================================================================

using DomeParams = fragment_math::DomeParams;
using PhysicsConfig = fragment_math::PhysicsConfig;

namespace ripple {

// Per-fragment physics data
struct PhysicsData {
  // Wave properties (same for all fragments)
  float waveFrequency;    // Cycles across dome (4-5)
  float waveAmplitude;    // How much fragments move in/out
  float rippleSpeed;      // How fast wavefront expands (raindrop ripple speed)

  // Detach properties (per-fragment random)
  float detachWaveCount;  // How many waves pass before detaching (2-6)
  float3 detachVelocity;  // Initial velocity when detaching
  float3 tumbleAxis;      // Rotation axis when detaching
  float tumbleSpeed;      // Rotation speed when detaching
  float gravity;          // Fall acceleration

  // Fade properties
  float fadeOutY;         // Y position where fragment disappears (40%-120% to zero)

};

// Read ripple-specific config from texture header
inline void readRippleConfig(
    thread const TextureParamReader& reader,
    thread float& waveFrequency,
    thread float& waveAmplitude,
    thread float& rippleSpeed
) {
  waveFrequency = reader.readFloat16<tex_param::WAVE_FREQUENCY>(1.0f, 10.0f);
  waveAmplitude = reader.readFloat16<tex_param::WAVE_AMPLITUDE>(0.0f, 0.2f);
  rippleSpeed   = reader.readFloat16<tex_param::RIPPLE_SPEED>(0.0f, 2.0f);
}

// Generate physics data
inline PhysicsData readPhysicsData(
    int fragmentIndex,
    thread const TextureParamReader& reader
) {
  PhysicsData pd;

  // Read shared physics config
  PhysicsConfig config = readPhysicsConfig(reader);

  // Read ripple-specific config (includes rippleSpeed)
  readRippleConfig(reader,
                   pd.waveFrequency, pd.waveAmplitude, pd.rippleSpeed);

  // Random detach: after 2-6 waves pass over the fragment (seed 300)
  pd.detachWaveCount = stable_random(fragmentIndex, 300, 2.0f, 6.0f);

  // Detach velocity: mostly tangent to surface with slight upward bias
  // First get a random tangent direction (seeds 301-302)
  float tangentAngle = stable_random(fragmentIndex, 301, 0.0f, 2.0f * M_PI_F);
  float upwardBias = stable_random(fragmentIndex, 302, 0.1f, 0.3f);  // Slight upward
  float speed = stable_random(fragmentIndex, 303, 0.1f, 0.4f);

  // We'll compute actual tangent in computeState based on position
  // Store the parameters here
  pd.detachVelocity = float3(tangentAngle, upwardBias, speed);

  // Tumble axis and speed for detached fragments (seeds 310-313)
  pd.tumbleAxis = normalize(float3(
    stable_random(fragmentIndex, 310, -1.0f, 1.0f),
    stable_random(fragmentIndex, 311, -1.0f, 1.0f),
    stable_random(fragmentIndex, 312, -1.0f, 1.0f)
  ) + float3(0.001f, 0.001f, 0.001f));
  pd.tumbleSpeed = stable_random(fragmentIndex, 313, config.spinRateMin, config.spinRateMax);

  // Gravity (random)
  pd.gravity = config.baseGravity * stable_random(fragmentIndex, 314, config.gravityMin, config.gravityMax);

  // Fade out Y: between 40% and 120% of the way to zero plane
  // fadeFactor 0.4 = fade at 60% height, 1.2 = fade at -20% height (below zero)
  float fadeFactor = stable_random(fragmentIndex, 320, 0.4f, 1.2f);
  pd.fadeOutY = fadeFactor;  // Store factor, compute actual Y in computeState

  return pd;
}

// Compute fragment state for ripple algorithm
inline RippleFragmentState computeState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  RippleFragmentState state;
  state.elapsed = time;

  // Compute fragment center from tessellation
  float3 center = computeCenterFromIndex(
    fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius
  );
  float3 normal = normalize(center);
  float initialY = center.y;

  // Distance from wave origin (for wave propagation)
  float distFromOrigin = length(center - dome.waveOrigin);

  // === WAVE MOTION ===
  // Expanding ripple from origin
  float wavefrontDist = physics.rippleSpeed * time;
  float waveOffset = 0.0f;
  float wavesPassed = 0.0f;

  if (distFromOrigin <= wavefrontDist) {
    // Spatial frequency: waves per unit distance
    float spatialFreq = physics.waveFrequency * 2.0f * M_PI_F / dome.radius;
    // Phase increases as wavefront passes
    float phase = spatialFreq * (wavefrontDist - distFromOrigin);
    waveOffset = physics.waveAmplitude * sin(phase);
    // Count how many complete waves have passed this fragment
    wavesPassed = phase / (2.0f * M_PI_F);
  }

  // === DETACH CHECK ===
  // Fragment detaches after N waves have passed over it
  bool hasDetached = wavesPassed >= physics.detachWaveCount;

  // Compute fadeOutY from factor: fadeFactor of 0.4 means fade at 60% of initialY
  // fadeFactor of 1.2 means fade at -20% of initialY (below zero)
  float fadeOutY = initialY * (1.0f - physics.fadeOutY);

  // === COMPUTE POSITION AND ROTATION ===

  if (!hasDetached) {
    // Still connected: wave motion only
    state.position = center + normal * waveOffset;
    state.normal = normal;
    state.rotation = float4(0, 0, 0, 1);
    state.visible = true;

    // Compute wave phase for material blending (0=trough, 0.5=rest, 1=peak)
    if (distFromOrigin <= wavefrontDist) {
      float spatialFreq = physics.waveFrequency * 2.0f * M_PI_F / dome.radius;
      float phase = spatialFreq * (wavefrontDist - distFromOrigin);
      float sinVal = sin(phase);
      state.wavePhase = (sinVal + 1.0f) * 0.5f;  // Normalize -1..1 to 0..1
    } else {
      state.wavePhase = 0.5f;  // At rest before wave arrives
    }
  }
  else {
    // Detached: fall straight down with tumble (Matrix-style letter drop)

    // Calculate when detachment happened (when wavesPassed == detachWaveCount)
    float spatialFreq = physics.waveFrequency * 2.0f * M_PI_F / dome.radius;
    float detachPhase = physics.detachWaveCount * 2.0f * M_PI_F;
    float detachWavefrontDist = detachPhase / spatialFreq + distFromOrigin;
    float detachTime = detachWavefrontDist / physics.rippleSpeed;
    float timeSinceDetach = max(0.0f, time - detachTime);

    // Position at detach (with wave offset at that moment)
    float detachWaveOffset = physics.waveAmplitude * sin(detachPhase);
    float3 detachPosition = center + normal * detachWaveOffset;

    // Fall straight down - no lateral velocity
    float t = timeSinceDetach;
    state.position = detachPosition + float3(0, -0.5f * physics.gravity * t * t, 0);

    // Rotation (tumble as it falls)
    float tumbleAngle = physics.tumbleSpeed * t;
    state.rotation = quatFromAxisAngle(physics.tumbleAxis, tumbleAngle);
    state.normal = quatRotate(state.rotation, normal);

    // Visible until we reach the fade-out Y position
    state.visible = state.position.y >= fadeOutY;

    // Detached fragments: neutral wave phase (blend of metal/glass)
    state.wavePhase = 0.5f;
  }

  return state;
}

// Convenience: compute minimal state for visibility checking
// Note: Uses FRAGMENT_CLIP_Y for visibility (not fadeOutY) so "all fragments gone"
// detection waits until fragments actually fall off screen, not when they fade.
inline FragmentState computeVisibilityState(
    int fragmentIndex,
    float time,
    DomeParams dome,
    PhysicsData physics
) {
  RippleFragmentState full = computeState(fragmentIndex, time, dome, physics);
  FragmentState fs;
  fs.position = full.position;
  fs.normal = full.normal;
  // Use standard clip plane for counting, not per-fragment fadeOutY
  fs.visible = full.position.y >= FRAGMENT_CLIP_Y;
  return fs;
}

}  // namespace ripple
