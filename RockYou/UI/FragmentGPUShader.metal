// FragmentGPUShader.metal
// RockYou
//
// GPU-driven fragment shatter system. All physics computed on GPU.
// Uses shared physics from DomeShatterPhysics.h - same math as visibility compute shader!
//
// custom_parameter layout (DYNAMIC values that change every frame):
//   .x = time (animation time in seconds)
//   .y = cameraX (for back-face detection)
//   .z = cameraY
//   .w = cameraZ
//
// Texture layout (16 x 4096) - STATIC values + lookup tables:
//   IMPORTANT: Texture MUST use LINEAR color space (not deviceRGB) to avoid gamma corruption!
//   Rows 0-4095: Random physics parameters (4096 entries)
//     Col 0: velocity.xyz [±0.5], gravity [±2]
//     Col 1: angularVelocity.xyz [±10], unused
//     Col 2: rotation quaternion [±1]
//   Header (row 0 only) - static dome/wave params:
//     Col 3: radius (RG 16-bit), latSegments (BA 16-bit)
//     Col 4: lonSegments (RG), waveSpeed (BA)
//     Col 5: waveOrigin.x (RG), waveOrigin.y (BA)
//     Col 6: waveOrigin.z (RG), waveEnabled (BA)

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "Shaders/DomeShatterPhysics.h"

using namespace metal;

// =============================================================================
// Texture decoding helpers (RealityKit texture sampler specific)
// =============================================================================

// Decode 16-bit value from two 8-bit texture samples (high, low bytes)
float decode16bit(float highByte, float lowByte, float minVal, float maxVal) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  float val16 = float(high * 256 + low);
  return val16 / 65535.0f * (maxVal - minVal) + minVal;
}

int decode16bitInt(float highByte, float lowByte) {
  int high = int(round(highByte * 255.0f));
  int low = int(round(lowByte * 255.0f));
  return high * 256 + low;
}

// =============================================================================
// Geometry modifier - transforms vertices based on physics simulation
// =============================================================================

[[visible]]
void fragmentGeometryModifier(realitykit::geometry_parameters params) {
  // Get custom parameters: (time, cameraX, cameraY, cameraZ)
  float4 customParams = params.uniforms().custom_parameter();
  float time = customParams.x;
  float3 cameraPos = float3(customParams.y, customParams.z, customParams.w);

  // Get data texture (contains static params + physics lookup tables)
  auto dataTexture = params.textures().custom();
  constexpr sampler texSampler(address::clamp_to_edge, filter::nearest);

  // Get texture dimensions for sampling
  float textureWidth = float(dataTexture.get_width());
  float textureHeight = float(dataTexture.get_height());

  // Read static header from texture (row 0)
  // Col 3: radius (RG), latSegments (BA)
  float2 h3UV = float2(3.5f / textureWidth, 0.5f / textureHeight);
  float4 h3 = float4(dataTexture.sample(texSampler, h3UV));
  float radius = decode16bit(h3.r, h3.g, 0.0f, 2.0f);
  int latSegments = decode16bitInt(h3.b, h3.a);

  // Col 4: lonSegments (RG), waveSpeed (BA)
  float2 h4UV = float2(4.5f / textureWidth, 0.5f / textureHeight);
  float4 h4 = float4(dataTexture.sample(texSampler, h4UV));
  int lonSegments = decode16bitInt(h4.r, h4.g);
  float waveSpeed = decode16bit(h4.b, h4.a, 0.0f, 20.0f);

  // Sanity check values - if clearly wrong, don't transform
  if (latSegments < 2 || latSegments > 10000 || lonSegments < 4 || lonSegments > 10000 || radius < 0.01f || radius > 10.0f) {
    return;  // No transform - keep dome intact but frozen
  }

  // Col 5: waveOrigin.x (RG), waveOrigin.y (BA)
  float2 h5UV = float2(5.5f / textureWidth, 0.5f / textureHeight);
  float4 h5 = float4(dataTexture.sample(texSampler, h5UV));
  float waveOriginX = decode16bit(h5.r, h5.g, -2.0f, 2.0f);
  float waveOriginY = decode16bit(h5.b, h5.a, -2.0f, 2.0f);

  // Col 6: waveOrigin.z (RG), waveEnabled (BA)
  float2 h6UV = float2(6.5f / textureWidth, 0.5f / textureHeight);
  float4 h6 = float4(dataTexture.sample(texSampler, h6UV));
  float waveOriginZ = decode16bit(h6.r, h6.g, -2.0f, 2.0f);
  int waveEnabled = decode16bitInt(h6.b, h6.a);

  float3 waveOrigin = float3(waveOriginX, waveOriginY, waveOriginZ);

  // Extract fragment index from UV (use round to avoid float precision issues)
  float2 uv = params.geometry().uv0();
  int fragmentIndex = int(round(uv.x));

  // COMPUTE center from fragment index using SHARED function
  float3 center = domeComputeCenterFromIndex(fragmentIndex, latSegments, lonSegments, radius);

  // COMPUTE spawnTime using SHARED function
  float spawnTime = domeComputeSpawnTime(center, waveOrigin, waveSpeed, waveEnabled);

  // Compute elapsed time since spawn
  float elapsed = max(0.0f, time - spawnTime);

  // Look up physics parameters from lookup tables using SHARED hash function
  int lookupIdx = dome_math::hashIndex(fragmentIndex, 42);

  // Velocity + gravity (col 0)
  float2 velUV = float2(0.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 velData = float4(dataTexture.sample(texSampler, velUV));
  float3 velocity = velData.xyz * 1.0f - 0.5f;  // Range [-0.5, 0.5]
  float baseGravity = velData.w * 4.0f - 2.0f;  // Range [-2, 2]

  // Add per-fragment noise to gravity to break up banding
  uint fragHash = uint(fragmentIndex) * 2654435761u;
  float gravityNoise = (float(fragHash & 0xFFFFu) / 65535.0f - 0.5f) * 0.02f;
  float gravity = baseGravity + gravityNoise;

  // Angular velocity (col 1)
  float2 angVelUV = float2(1.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 angVelData = float4(dataTexture.sample(texSampler, angVelUV));
  float3 angularVelocity = angVelData.xyz * 20.0f - 10.0f;  // Range [-10, 10]

  // Initial rotation quaternion (col 2)
  float2 rotUV = float2(2.5f / textureWidth, (float(lookupIdx) + 0.5f) / textureHeight);
  float4 rotData = float4(dataTexture.sample(texSampler, rotUV));
  float4 initialRotation = normalize(rotData * 2.0f - 1.0f);  // Range [-1, 1], normalized

  // COMPUTE position using SHARED function
  float3 newCenter = domeComputePosition(center, velocity, gravity, elapsed);

  // Clip fragments below clip plane (uses SHARED constant)
  if (newCenter.y < FRAGMENT_CLIP_Y) {
    params.geometry().set_model_position_offset(float3(0, -1000, 0));
    return;
  }

  // Get vertex position (world position - mesh has actual dome positions)
  float3 localPos = params.geometry().model_position();
  float3 normal = params.geometry().normal();

  // At t=0 (elapsed=0), no movement - dome stays intact
  if (elapsed <= 0.0f) {
    float3 viewDir = normalize(cameraPos - center);
    bool backFacing = dot(normal, viewDir) < 0.0f;
    params.geometry().set_uv0(float2(uv.x, backFacing ? 1.0f : 0.0f));
    return;
  }

  // Compute rotation using SHARED quaternion functions
  float angSpeed = length(angularVelocity);
  float4 spinRotation = float4(0, 0, 0, 1);  // Identity
  if (angSpeed > 0.001f) {
    float3 spinAxis = angularVelocity / angSpeed;
    float spinAngle = angSpeed * elapsed;
    spinRotation = dome_math::quatFromAxisAngle(spinAxis, spinAngle);
  }

  // Combined rotation using SHARED quatMul
  float4 totalRotation = normalize(dome_math::quatMul(spinRotation, initialRotation));

  // Rotate vertex around fragment center using SHARED quatRotate
  float3 relativePos = localPos - center;
  float3 rotatedRelative = dome_math::quatRotate(totalRotation, relativePos);
  float3 rotatedNormal = dome_math::quatRotate(totalRotation, normal);

  // Final world position: rotated position + physics offset
  float3 positionOffset = newCenter - center;
  float3 finalWorldPos = (center + rotatedRelative) + positionOffset;
  float3 finalOffset = finalWorldPos - localPos;
  params.geometry().set_model_position_offset(finalOffset);

  // Detect back-facing: normal pointing away from camera
  float3 viewDir = normalize(cameraPos - newCenter);
  bool backFacing = dot(rotatedNormal, viewDir) < 0.0f;

  // Flip normal for back faces so lighting works correctly
  float3 finalNormal = backFacing ? -rotatedNormal : rotatedNormal;
  params.geometry().set_normal(finalNormal);

  // Pass back-facing flag to surface shader via uv0.y
  params.geometry().set_uv0(float2(uv.x, backFacing ? 1.0f : 0.0f));
}

// =============================================================================
// Surface shader - glass on front, metal on back
// =============================================================================

[[visible]]
void fragmentGPUSurfaceShader(realitykit::surface_parameters params) {
  float2 uv = params.geometry().uv0();
  bool backFacing = uv.y > 0.5f;

  if (backFacing) {
    // Glass appearance (back faces)
    params.surface().set_base_color(half3(0.1h, 0.12h, 0.15h));
    params.surface().set_opacity(0.15h);
    params.surface().set_roughness(0.05h);
    params.surface().set_metallic(0.0h);
    params.surface().set_specular(0.8h);
  } else {
    // Metal appearance (front faces)
    params.surface().set_base_color(half3(0.75h, 0.75h, 0.8h));
    params.surface().set_opacity(1.0h);
    params.surface().set_roughness(0.15h);
    params.surface().set_metallic(0.9h);
    params.surface().set_specular(0.5h);
  }
}
