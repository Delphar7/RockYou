// IrisSeamShader.metal
// RockYou
//
// Seam ribbon shader for iris mechanism.
// Seams are plane-sphere intersection circles — parameterized analytically.
// Uses general basis vectors (not constrained to XZ plane like sphere model).
// Tangent is the exact derivative of the circle parameterization.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "Algorithms/IrisAlgorithm.h"

using namespace metal;

// Geometry modifier: positions ribbon vertices along seam arcs
[[visible]]
void irisSeamGeometryModifier(realitykit::geometry_parameters params) {
  float4 customParams = params.uniforms().custom_parameter();
  float time = customParams.x;

  auto dataTexture = params.textures().custom();
  float texWidth = float(dataTexture.get_width());
  float texHeight = float(dataTexture.get_height());
  TextureParamReader reader = { dataTexture, 1.0f / texWidth, 1.0f / texHeight };

  fragment_math::DomeParams dome = fragment_math::readDomeParams(reader);
  iris::PhysicsData physics = iris::readPhysicsData(0, reader);

  // Decode UV: x = arcT (0-1), y = bladeIndex + widthSign*0.25
  float2 uv = params.geometry().uv0();
  float arcT = uv.x;
  int bladeIndex = int(floor(uv.y));
  float widthSign = (fract(uv.y) > 0.1f) ? 1.0f : -1.0f;

  // Compute threshold from time (t=0 → closed, t=openDuration → -0.9R)
  float threshold = iris::computeThreshold(
    time, physics.openDuration,
    physics.bladeCount, physics.radius, physics.elevation
  );

  // Phase 2: elevation ramp to clear equatorial seams (matches dome fragments)
  float effectiveElevation = iris::computePhase2Elevation(
    time, physics.openDuration, physics.elevation
  );

  // Compute seam point and analytical tangent in one call
  iris::SeamPointResult seamResult = iris::computeSeamPointAndTangent(
    bladeIndex, arcT, threshold,
    physics.bladeCount, physics.radius,
    physics.tilt, effectiveElevation
  );

  float3 pos3D = seamResult.position;

  // Hide vertex if seam computation returned hidden marker
  if (!seamResult.valid) {
    float3 meshPos = params.geometry().model_position();
    params.geometry().set_model_position_offset(float3(0, -1000.0f, 0) - meshPos);
    return;
  }

  // Normal is outward from dome center
  float3 normal = normalize(pos3D);

  float3 tangentDir = seamResult.tangent;
  // Project onto tangent plane
  tangentDir = tangentDir - normal * dot(tangentDir, normal);
  float tangentLen = length(tangentDir);

  // Compute binormal
  float2 radialXZ = float2(pos3D.x, pos3D.z);
  float radialLen = length(radialXZ);

  float3 binormal;
  if (tangentLen > 0.0001f) {
    float3 tangent = tangentDir / tangentLen;
    binormal = normalize(cross(normal, tangent));
  } else if (radialLen > 0.001f) {
    float2 circumXZ = float2(-radialXZ.y, radialXZ.x) / radialLen;
    binormal = normalize(float3(circumXZ.x, 0, circumXZ.y));
  } else {
    binormal = float3(1, 0, 0);
  }

  // Taper ribbon width near apex
  float apexTaper = smoothstep(0.0f, 0.15f, radialLen / dome.radius);
  float ribbonWidth = 0.003f * apexTaper;
  float3 offsetPos = pos3D + binormal * widthSign * ribbonWidth;

  // Re-project to dome surface + outward offset for z-fighting avoidance
  float3 finalPos = normalize(offsetPos) * (dome.radius + 0.008f);

  float3 meshPos = params.geometry().model_position();
  params.geometry().set_model_position_offset(finalPos - meshPos);
  params.geometry().set_normal(normal);
  // Phase 2 Y-clipping is handled in computeSeamPointAndTangent (valid=false).
  // No drop phase needed — seams disappear naturally via elevation ramp.
  // UV1.y = 1 signals exterior arc (wrong side) — surface shader renders red.
  params.geometry().set_uv1(float2(1.0f, seamResult.interiorArc ? 0.0f : 1.0f));
}

// Color palette for blade boundaries
constant half3 irisRibbonPalette[] = {
  half3(0.9h, 0.3h, 0.3h),  // Red
  half3(0.9h, 0.6h, 0.2h),  // Orange
  half3(0.9h, 0.9h, 0.3h),  // Yellow
  half3(0.4h, 0.9h, 0.4h),  // Green
  half3(0.3h, 0.7h, 0.9h),  // Cyan
  half3(0.4h, 0.4h, 0.9h),  // Blue
  half3(0.7h, 0.3h, 0.9h),  // Purple
  half3(0.9h, 0.4h, 0.7h),  // Pink
  half3(1.0h, 0.5h, 0.5h),
  half3(0.5h, 1.0h, 0.5h),
  half3(0.5h, 0.5h, 1.0h),
  half3(1.0h, 1.0h, 0.5h),
};

// Surface shader: colored by blade index.
// Renders bright red if the arc is exterior (Y axis on the wrong side) —
// this should never happen in correct operation.
[[visible]]
void irisSeamSurfaceShader(realitykit::surface_parameters params) {
  float2 uv1 = params.geometry().uv1();
  bool exteriorArc = uv1.y > 0.5f;

  if (exteriorArc) {
    params.surface().set_base_color(half3(1.0h, 0.0h, 0.0h));
    params.surface().set_emissive_color(half3(1.0h, 0.0h, 0.0h));
    params.surface().set_metallic(0.0h);
    params.surface().set_roughness(1.0h);
    params.surface().set_specular(0.0h);
    params.surface().set_opacity(1.0h);
    return;
  }

  float2 uv = params.geometry().uv0();
  int bladeIndex = int(floor(uv.y));
  int colorIndex = bladeIndex % 12;

  half3 color = irisRibbonPalette[colorIndex];

  params.surface().set_base_color(color);
  params.surface().set_metallic(0.0h);
  params.surface().set_roughness(0.3h);
  params.surface().set_specular(0.5h);
  params.surface().set_opacity(1.0h);
}
