// FragmentState.h
// RockYou
//
// Shared interface for fragment-based animations.
// Every animation that wants visibility checking must return this struct.

#ifndef FRAGMENT_STATE_H
#define FRAGMENT_STATE_H

#include <metal_stdlib>
using namespace metal;

/// State of a single fragment at a given time.
/// Animations compute this for both rendering (geometry modifier) and visibility checking (compute).
struct FragmentState {
    float3 position;    // World position after physics/animation
    float3 normal;      // Surface normal (may be rotated)
    bool visible;       // Should this fragment be rendered? (above clip plane, spawned, etc.)
};

/// Clip plane Y - fragments below this are considered invisible
constant float FRAGMENT_CLIP_Y = -0.1f;

#endif // FRAGMENT_STATE_H
