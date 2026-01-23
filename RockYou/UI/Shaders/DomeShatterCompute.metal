// DomeShatterCompute.metal
// RockYou
//
// Compute shader for dome shatter visibility checking.
// Uses shared physics header - same math as geometry modifier!

#include <metal_stdlib>
#include "DomeShatterPhysics.h"

using namespace metal;

// =============================================================================
// Texture decoding helpers (same as geometry modifier)
// =============================================================================

float dome_decode16bit(float highByte, float lowByte, float minVal, float maxVal) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  float val16 = float(high * 256 + low);
  return val16 / 65535.0f * (maxVal - minVal) + minVal;
}

int dome_decode16bitInt(float highByte, float lowByte) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  return high * 256 + low;
}

// =============================================================================
// Visibility kernel - reads from same texture as geometry modifier
// =============================================================================

kernel void domeShatter_visibility_texture(
    device atomic_uint* anyVisible [[buffer(0)]],
    constant float& time [[buffer(1)]],
    constant uint& fragmentCount [[buffer(2)]],
    texture2d<float, access::sample> dataTexture [[texture(0)]],
    uint idx [[thread_position_in_grid]]
) {
  if (idx >= fragmentCount) return;

  constexpr sampler texSampler(address::clamp_to_edge, filter::nearest);
  float textureWidth = float(dataTexture.get_width());
  float textureHeight = float(dataTexture.get_height());

  // Read static header from texture (row 0)
  float2 h3UV = float2(3.5f / textureWidth, 0.5f / textureHeight);
  float4 h3 = dataTexture.sample(texSampler, h3UV);
  float radius = dome_decode16bit(h3.r, h3.g, 0.0f, 2.0f);
  int latSegments = dome_decode16bitInt(h3.b, h3.a);

  float2 h4UV = float2(4.5f / textureWidth, 0.5f / textureHeight);
  float4 h4 = dataTexture.sample(texSampler, h4UV);
  int lonSegments = dome_decode16bitInt(h4.r, h4.g);
  float waveSpeed = dome_decode16bit(h4.b, h4.a, 0.0f, 20.0f);

  float2 h5UV = float2(5.5f / textureWidth, 0.5f / textureHeight);
  float4 h5 = dataTexture.sample(texSampler, h5UV);
  float waveOriginX = dome_decode16bit(h5.r, h5.g, -2.0f, 2.0f);
  float waveOriginY = dome_decode16bit(h5.b, h5.a, -2.0f, 2.0f);

  float2 h6UV = float2(6.5f / textureWidth, 0.5f / textureHeight);
  float4 h6 = dataTexture.sample(texSampler, h6UV);
  float waveOriginZ = dome_decode16bit(h6.r, h6.g, -2.0f, 2.0f);
  int waveEnabled = dome_decode16bitInt(h6.b, h6.a);

  // Build params struct
  DomeShatterParams params;
  params.radius = radius;
  params.latSegments = latSegments;
  params.lonSegments = lonSegments;
  params.waveSpeed = waveSpeed;
  params.waveOrigin = float3(waveOriginX, waveOriginY, waveOriginZ);
  params.waveEnabled = waveEnabled;

  // Look up physics from texture using SHARED hash function
  int lookupIdx = dome_math::hashIndex(int(idx), 42);

  float2 velUV = float2(0.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 velData = dataTexture.sample(texSampler, velUV);

  float2 angVelUV = float2(1.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 angVelData = dataTexture.sample(texSampler, angVelUV);

  float2 rotUV = float2(2.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 rotData = dataTexture.sample(texSampler, rotUV);

  // Build physics data (same decoding as geometry modifier)
  DomeFragmentPhysicsData physics;
  physics.velocity = velData.xyz * 1.0f - 0.5f;

  float baseGravity = velData.w * 4.0f - 2.0f;
  uint fragHash = uint(idx) * 2654435761u;
  float gravityNoise = (float(fragHash & 0xFFFFu) / 65535.0f - 0.5f) * 0.02f;
  physics.gravity = baseGravity + gravityNoise;

  physics.angularVelocity = angVelData.xyz * 20.0f - 10.0f;
  physics.initialRotation = normalize(rotData * 2.0f - 1.0f);

  // Compute state using SHARED physics function
  FragmentState state = domeComputeFragmentState(int(idx), time, params, physics);

  if (state.visible) {
    atomic_store_explicit(anyVisible, 1u, memory_order_relaxed);
  }
}
