// IrisShader.metal
// RockYou
//
// Iris mechanism shader.
// Blade coverage uses dot(Q, n_i) > threshold (half-space checks).
// Supports spiral seams via tilt parameter.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "FragmentShaderScaffold.h"
#include "Algorithms/IrisAlgorithm.h"

using namespace metal;

// Geometry modifier for iris dome fragments
[[visible]]
void irisGeometryModifier(realitykit::geometry_parameters params) {
  float4 customParams = params.uniforms().custom_parameter();
  float time = customParams.x;
  float3 cameraPos = float3(customParams.y, customParams.z, customParams.w);

  auto dataTexture = params.textures().custom();
  float texWidth = float(dataTexture.get_width());
  float texHeight = float(dataTexture.get_height());
  TextureParamReader reader = { dataTexture, 1.0f / texWidth, 1.0f / texHeight };

  float2 uv = params.geometry().uv0();
  int fragmentIndex = int(round(uv.x));

  fragment_math::DomeParams dome = fragment_math::readDomeParams(reader);
  iris::PhysicsData physics = iris::readPhysicsData(fragmentIndex, reader);

  IrisFragmentState state = iris::computeState(fragmentIndex, time, dome, physics);

  if (!state.visible) {
    params.geometry().set_model_position_offset(float3(0, -1000.0f, 0));
    return;
  }

  // Apply position offset
  float3 center = fragment_math::computeCenterFromIndex(fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius);
  float3 offset = state.position - center;
  params.geometry().set_model_position_offset(offset);

  // Backface check
  float3 normal = params.geometry().normal();
  float3 viewDir = normalize(cameraPos - center);
  bool backFacing = dot(normal, viewDir) < 0.0f;

  float3 finalNormal = backFacing ? -normal : normal;
  params.geometry().set_normal(finalNormal);

  // Pass blade index and paramError to surface shader via UV1
  params.geometry().set_uv1(float2(float(state.bladeIndex), state.paramError ? 1.0f : 0.0f));
}

FRAGMENT_VISIBILITY_KERNEL(iris, iris)

// HSV to RGB for rainbow blade tints
inline half3 hsv2rgb_iris(half h, half s, half v) {
  half c = v * s;
  half x = c * (1.0h - abs(fmod(h * 6.0h, 2.0h) - 1.0h));
  half m = v - c;

  half3 rgb;
  if (h < 1.0h/6.0h)      rgb = half3(c, x, 0);
  else if (h < 2.0h/6.0h) rgb = half3(x, c, 0);
  else if (h < 3.0h/6.0h) rgb = half3(0, c, x);
  else if (h < 4.0h/6.0h) rgb = half3(0, x, c);
  else if (h < 5.0h/6.0h) rgb = half3(x, 0, c);
  else                     rgb = half3(c, 0, x);

  return rgb + m;
}

// Surface shader: rainbow-tinted glass
[[visible]]
void irisSurfaceShader(realitykit::surface_parameters params) {
  float3 normal = params.geometry().normal();
  float3 view = params.geometry().view_direction();
  bool backFacing = dot(normal, view) < 0.0f;

  float2 uv1 = params.geometry().uv1();
  int bladeIndex = int(uv1.x);
  bool paramError = uv1.y > 0.5f;

  // Error state: bright magenta to signal bad texture data
  if (paramError) {
    params.surface().set_base_color(half3(1.0h, 0.0h, 1.0h));
    params.surface().set_emissive_color(half3(0.5h, 0.0h, 0.5h));
    params.surface().set_metallic(0.0h);
    params.surface().set_roughness(1.0h);
    params.surface().set_specular(0.0h);
    params.surface().set_opacity(1.0h);
    return;
  }

  half hue = half(bladeIndex) / 12.0h;
  half3 tintColor = hsv2rgb_iris(hue, 0.7h, 1.0h);

  params.surface().set_base_color(tintColor * 0.15h);
  params.surface().set_metallic(0.0h);
  params.surface().set_roughness(0.01h);
  params.surface().set_specular(1.0h);
  params.surface().set_opacity(backFacing ? 0.06h : 0.12h);
}
