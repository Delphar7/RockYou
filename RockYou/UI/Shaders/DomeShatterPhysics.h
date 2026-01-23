// DomeShatterPhysics.h
// RockYou
//
// Shared physics for dome shatter animation.
// Included by both geometry modifier (for rendering) and compute shader (for visibility).

#ifndef DOME_SHATTER_PHYSICS_H
#define DOME_SHATTER_PHYSICS_H

#include <metal_stdlib>
#include "FragmentState.h"

using namespace metal;

// =============================================================================
// Configuration passed from Swift
// =============================================================================

struct DomeShatterParams {
    float radius;
    int latSegments;
    int lonSegments;
    float waveSpeed;
    float3 waveOrigin;
    int waveEnabled;
};

// =============================================================================
// Per-fragment physics data (from lookup table texture or buffer)
// =============================================================================

struct DomeFragmentPhysicsData {
    float3 velocity;      // Initial velocity
    float gravity;        // Gravity multiplier
    float3 angularVelocity;
    float4 initialRotation;  // Quaternion
};

// =============================================================================
// Math helpers
// =============================================================================

namespace dome_math {

// Simple integer hash for randomizing lookup indices
inline int hashIndex(int x, int seed) {
    uint input = uint(x + seed * 7919);
    uint state = input * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    uint result = (word >> 22u) ^ word;
    return int(result % 4096u);  // LOOKUP_TABLE_SIZE
}

// Quaternion multiplication
inline float4 quatMul(float4 q1, float4 q2) {
    return float4(
        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
        q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
    );
}

// Rotate vector by quaternion
inline float3 quatRotate(float4 q, float3 v) {
    float3 qv = float3(q.x, q.y, q.z);
    float3 uv = cross(qv, v);
    float3 uuv = cross(qv, uv);
    return v + ((uv * q.w) + uuv) * 2.0f;
}

// Create quaternion from axis-angle
inline float4 quatFromAxisAngle(float3 axis, float angle) {
    float halfAngle = angle * 0.5f;
    float s = sin(halfAngle);
    return float4(axis * s, cos(halfAngle));
}

}  // namespace dome_math

// =============================================================================
// Core physics computation
// =============================================================================

/// Compute triangle center from fragment index using dome tessellation math.
/// Must match Swift's createTessellatedMesh exactly!
inline float3 domeComputeCenterFromIndex(int fragmentIndex, int latSegments, int lonSegments, float radius) {
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

/// Compute spawn time based on wave propagation from origin.
inline float domeComputeSpawnTime(float3 center, float3 waveOrigin, float waveSpeed, int waveEnabled) {
    if (waveEnabled == 0 || waveSpeed <= 0.001f) {
        return 0.0f;
    }
    float dist = length(center - waveOrigin);
    return dist / waveSpeed;
}

/// Compute fragment position after physics simulation.
/// Returns the new center position.
inline float3 domeComputePosition(float3 center, float3 velocity, float gravity, float elapsed) {
    // Physics: position = center + velocity * t - 0.5 * gravity * t^2
    float3 positionOffset = velocity * elapsed + float3(0, -0.5f * abs(gravity) * elapsed * elapsed, 0);
    return center + positionOffset;
}

/// Compute fragment state for visibility checking.
/// This is the main function used by both geometry modifier and compute shader.
/// Uses thread-local params (passed by value) for flexibility with different kernel types.
inline FragmentState domeComputeFragmentState(
    int fragmentIndex,
    float time,
    DomeShatterParams params,
    DomeFragmentPhysicsData physics
) {
    FragmentState state;

    // Compute center from tessellation
    float3 center = domeComputeCenterFromIndex(
        fragmentIndex,
        params.latSegments,
        params.lonSegments,
        params.radius
    );

    // Compute spawn time from wave
    float spawnTime = domeComputeSpawnTime(
        center,
        params.waveOrigin,
        params.waveSpeed,
        params.waveEnabled
    );

    // Elapsed time since spawn
    float elapsed = max(0.0f, time - spawnTime);

    // Before spawn: fragment at original position, visible
    if (elapsed <= 0.0f) {
        state.position = center;
        state.normal = normalize(center);  // Dome normal points outward
        state.visible = true;
        return state;
    }

    // After spawn: apply physics
    state.position = domeComputePosition(center, physics.velocity, physics.gravity, elapsed);

    // Compute rotated normal
    float angSpeed = length(physics.angularVelocity);
    float4 rotation = physics.initialRotation;
    if (angSpeed > 0.001f) {
        float3 spinAxis = physics.angularVelocity / angSpeed;
        float spinAngle = angSpeed * elapsed;
        float4 spinRotation = dome_math::quatFromAxisAngle(spinAxis, spinAngle);
        rotation = normalize(dome_math::quatMul(spinRotation, physics.initialRotation));
    }
    state.normal = dome_math::quatRotate(rotation, normalize(center));

    // Visibility: above clip plane
    state.visible = state.position.y >= FRAGMENT_CLIP_Y;

    return state;
}

#endif // DOME_SHATTER_PHYSICS_H
