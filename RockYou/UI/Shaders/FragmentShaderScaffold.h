// FragmentShaderScaffold.h
// RockYou
//
// Scaffolding for GPU-driven fragment animation shaders.
// Each algorithm .metal file includes this and uses the macro to generate
// its geometry modifier. This eliminates runtime algorithm dispatch.
//
// custom_parameter layout (DYNAMIC values that change every frame):
//   .x = time (animation time in seconds)
//   .y = cameraX (for back-face detection)
//   .z = cameraY
//   .w = cameraZ
//
// Texture layout: see TextureParams.h for the virtual byte buffer format.

#pragma once

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "FragmentMath.h"

using namespace metal;
using namespace fragment_math;

// =============================================================================
// Geometry Modifier Macro
// =============================================================================
//
// Usage in algorithm .metal files:
//   #include "FragmentShaderScaffold.h"
//   #include "Algorithms/ExplodeAlgorithm.h"
//   FRAGMENT_GEOMETRY_MODIFIER(explode, explode)
//
// This generates: void explodeGeometryModifier(realitykit::geometry_parameters params)
//
// Parameters:
//   name - Prefix for the generated function (e.g., "explode" -> "explodeGeometryModifier")
//   AlgoNS - Namespace containing readPhysicsData() and computeState()

#define FRAGMENT_GEOMETRY_MODIFIER(name, AlgoNS) \
[[visible]] \
void name##GeometryModifier(realitykit::geometry_parameters params) { \
  float4 customParams = params.uniforms().custom_parameter(); \
  float time = customParams.x; \
  float3 cameraPos = float3(customParams.y, customParams.z, customParams.w); \
  \
  auto dataTexture = params.textures().custom(); \
  float texWidth = float(dataTexture.get_width()); \
  float texHeight = float(dataTexture.get_height()); \
  TextureParamReader reader = { dataTexture, 1.0f / texWidth, 1.0f / texHeight }; \
  \
  float2 uv = params.geometry().uv0(); \
  int fragmentIndex = int(round(uv.x)); \
  \
  DomeParams dome = readDomeParams(reader); \
  if (dome.latSegments < 2 || dome.lonSegments < 4 || dome.radius < 0.01f) { \
    return; \
  } \
  \
  auto physics = AlgoNS::readPhysicsData(fragmentIndex, reader); \
  auto state = AlgoNS::computeState(fragmentIndex, time, dome, physics); \
  \
  float3 newCenter = state.position; \
  float4 rotation = state.rotation; \
  float elapsed = state.elapsed; \
  bool visible = state.visible; \
  \
  if (!visible) { \
    params.geometry().set_model_position_offset(float3(0, -1000, 0)); \
    return; \
  } \
  \
  float3 localPos = params.geometry().model_position(); \
  float3 normal = params.geometry().normal(); \
  float3 center = computeCenterFromIndex(fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius); \
  \
  if (elapsed <= 0.0f) { \
    float3 viewDir = normalize(cameraPos - center); \
    bool backFacing = dot(normal, viewDir) < 0.0f; \
    params.geometry().set_uv0(float2(uv.x, backFacing ? 1.0f : 0.0f)); \
    return; \
  } \
  \
  float3 relativePos = localPos - center; \
  float3 rotatedRelative = quatRotate(rotation, relativePos); \
  float3 rotatedNormal = quatRotate(rotation, normal); \
  \
  float3 positionOffset = newCenter - center; \
  float3 finalWorldPos = (center + rotatedRelative) + positionOffset; \
  float3 finalOffset = finalWorldPos - localPos; \
  params.geometry().set_model_position_offset(finalOffset); \
  \
  float3 viewDir = normalize(cameraPos - newCenter); \
  bool backFacing = dot(rotatedNormal, viewDir) < 0.0f; \
  \
  float3 finalNormal = backFacing ? -rotatedNormal : rotatedNormal; \
  params.geometry().set_normal(finalNormal); \
  params.geometry().set_uv0(float2(uv.x, backFacing ? 1.0f : 0.0f)); \
}

// =============================================================================
// Visibility Kernel Macro
// =============================================================================
//
// Usage in algorithm .metal files (after FRAGMENT_GEOMETRY_MODIFIER):
//   FRAGMENT_VISIBILITY_KERNEL(explode, explode)
//
// This generates: kernel void explodeVisibilityKernel(...)
//
// Parameters:
//   name - Prefix for the generated function (e.g., "explode" -> "explodeVisibilityKernel")
//   AlgoNS - Namespace containing readPhysicsData() and computeVisibilityState()

#define FRAGMENT_VISIBILITY_KERNEL(name, AlgoNS) \
[[kernel]] \
void name##VisibilityKernel( \
    device atomic_uint* anyVisible [[buffer(0)]], \
    constant float& time [[buffer(1)]], \
    constant uint& fragmentCount [[buffer(2)]], \
    texture2d<half, access::sample> dataTexture [[texture(0)]], \
    uint idx [[thread_position_in_grid]] \
) { \
  if (idx >= fragmentCount) return; \
  \
  float texWidth = float(dataTexture.get_width()); \
  float texHeight = float(dataTexture.get_height()); \
  TextureParamReader reader = { dataTexture, 1.0f / texWidth, 1.0f / texHeight }; \
  \
  DomeParams dome = readDomeParams(reader); \
  auto physics = AlgoNS::readPhysicsData(int(idx), reader); \
  FragmentState state = AlgoNS::computeVisibilityState(int(idx), time, dome, physics); \
  \
  if (state.visible) { \
    atomic_store_explicit(anyVisible, 1u, memory_order_relaxed); \
  } \
}
