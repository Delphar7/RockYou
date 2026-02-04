// RippleShader.metal
// RockYou
//
// Ripple algorithm shader: Wave motion, random detach, fall with tumble.
// Custom geometry modifier passes wave phase for material blending.
// Surface shader blends between metal (troughs) and glass (peaks).

#include "FragmentShaderScaffold.h"
#include "Algorithms/RippleAlgorithm.h"

// =============================================================================
// Ripple Geometry Modifier (custom - passes wavePhase via UV)
// =============================================================================

[[visible]]
void rippleGeometryModifier(realitykit::geometry_parameters params) {
  float4 customParams = params.uniforms().custom_parameter();
  float time = customParams.x;
  float3 cameraPos = float3(customParams.y, customParams.z, customParams.w);

  auto dataTexture = params.textures().custom();
  float texWidth = float(dataTexture.get_width());
  float texHeight = float(dataTexture.get_height());
  TextureParamReader reader = { dataTexture, 1.0f / texWidth, 1.0f / texHeight };

  float2 uv = params.geometry().uv0();
  int fragmentIndex = int(round(uv.x));

  DomeParams dome = readDomeParams(reader);
  if (dome.latSegments < 2 || dome.lonSegments < 4 || dome.radius < 0.01f) {
    return;
  }

  auto physics = ripple::readPhysicsData(fragmentIndex, reader);
  auto state = ripple::computeState(fragmentIndex, time, dome, physics);

  float3 newCenter = state.position;
  float4 rotation = state.rotation;
  float elapsed = state.elapsed;
  bool visible = state.visible;
  float wavePhase = state.wavePhase;

  if (!visible) {
    params.geometry().set_model_position_offset(float3(0, -1000, 0));
    return;
  }

  float3 localPos = params.geometry().model_position();
  float3 normal = params.geometry().normal();
  float3 center = computeCenterFromIndex(fragmentIndex, dome.latSegments, dome.lonSegments, dome.radius);

  if (elapsed <= 0.0f) {
    float3 viewDir = normalize(cameraPos - center);
    bool backFacing = dot(normal, viewDir) < 0.0f;
    // Encode: wavePhase (0-1) + backFacing offset (10.0)
    float uvY = wavePhase + (backFacing ? 10.0f : 0.0f);
    params.geometry().set_uv0(float2(uv.x, uvY));
    return;
  }

  float3 relativePos = localPos - center;
  float3 rotatedRelative = quatRotate(rotation, relativePos);
  float3 rotatedNormal = quatRotate(rotation, normal);

  float3 positionOffset = newCenter - center;
  float3 finalWorldPos = (center + rotatedRelative) + positionOffset;
  float3 finalOffset = finalWorldPos - localPos;
  params.geometry().set_model_position_offset(finalOffset);

  float3 viewDir = normalize(cameraPos - newCenter);
  bool backFacing = dot(rotatedNormal, viewDir) < 0.0f;

  float3 finalNormal = backFacing ? -rotatedNormal : rotatedNormal;
  params.geometry().set_normal(finalNormal);

  // Encode: wavePhase (0-1) + backFacing offset (10.0)
  float uvY = wavePhase + (backFacing ? 10.0f : 0.0f);
  params.geometry().set_uv0(float2(uv.x, uvY));
}

// =============================================================================
// Ripple Visibility Kernel (use standard macro)
// =============================================================================

FRAGMENT_VISIBILITY_KERNEL(ripple, ripple)

// =============================================================================
// Ripple Surface Shader - Metal/Glass blend based on wave phase
// =============================================================================
//
// Wave phase: 0 = trough (metal), 0.5 = rest (blend), 1 = peak (glass)
// Material properties interpolated smoothly between the two.

[[visible]]
void rippleSurfaceShader(realitykit::surface_parameters params) {
  float2 uv = params.geometry().uv0();

  // Decode wavePhase and backFacing from uv.y
  // Encoding: wavePhase (0-1) + backFacing offset (10.0)
  bool backFacing = uv.y >= 5.0f;
  float wavePhase = fmod(uv.y, 10.0f);
  wavePhase = clamp(wavePhase, 0.0f, 1.0f);

  // wavePhase: 0 = trough (sin=-1), 0.5 = rest, 1 = peak (sin=1)
  // We want: base/rest/peak = metal, only troughs = clear glass
  // Glass only appears when wavePhase < 0.4 (the valleys)
  float glassAmount = smoothstep(0.4f, 0.1f, wavePhase);

  // Material properties
  // Metal (peak): metallic, opaque, reflective
  // Glass (trough): non-metallic, clear, high specular

  // Base colors
  half3 metalColor = half3(0.85h, 0.85h, 0.9h);   // Cool silver
  half3 glassColor = half3(0.02h, 0.02h, 0.03h);  // Nearly black - clear glass has no diffuse color

  // Interpolate properties
  half3 baseColor = mix(metalColor, glassColor, half(glassAmount));
  half metallic = mix(0.95h, 0.0h, half(glassAmount));
  half roughness = mix(0.15h, 0.02h, half(glassAmount));  // Glass is very smooth
  half opacity = mix(1.0h, 0.1h, half(glassAmount));      // Glass is nearly clear
  half specular = mix(0.5h, 1.0h, half(glassAmount));     // Glass has high specular

  // Back faces: pure clear glass
  if (backFacing) {
    baseColor = half3(0.02h, 0.02h, 0.03h);
    roughness = 0.02h;
    metallic = 0.0h;
    specular = 0.1h;
    opacity = 0.05h;
  }

  params.surface().set_base_color(baseColor);
  params.surface().set_metallic(metallic);
  params.surface().set_roughness(roughness);
  params.surface().set_opacity(opacity);
  params.surface().set_specular(specular);
}
