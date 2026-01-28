// IrisSeamRibbonShader.metal
// RockYou
//
// Ribbon geometry for iris blade seams.
// Crisp lines that follow blade boundaries by deforming ribbon mesh vertices.
// Uses shared functions from IrisAlgorithm.h.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "Algorithms/IrisAlgorithm.h"
#include "Algorithms/IrisSeamProjection.h"

using namespace metal;

// Geometry modifier: positions ribbon vertices along blade boundary arcs
[[visible]]
void irisSeamRibbonGeometryModifier(realitykit::geometry_parameters params) {
  float4 customParams = params.uniforms().custom_parameter();
  float time = customParams.x;

  auto dataTexture = params.textures().custom();
  constexpr sampler texSampler(address::clamp_to_edge, filter::nearest);
  float texWidth = float(dataTexture.get_width());
  float texHeight = float(dataTexture.get_height());

  // Read parameters using shared functions
  fragment_math::DomeParams dome = fragment_math::readDomeParams(dataTexture, texSampler, texWidth, texHeight);
  iris::PhysicsData physics = iris::readPhysicsData(0, dataTexture, texSampler, texWidth, texHeight);

  // Decode UV: x = arcT (0-1), y = bladeIndex + widthSign*0.25
  float2 uv = params.geometry().uv0();
  float arcT = uv.x;
  int bladeIndex = int(floor(uv.y));
  float widthSign = (fract(uv.y) > 0.1f) ? 1.0f : -1.0f;

  // Compute aperture (uses configurable openDuration)
  float aperture = 1.0f - clamp(time / physics.openDuration, 0.0f, 1.0f);

  // Compute seam point using unified projection
  float3 pos3D = iris_projection::computeSeamPoint(
    bladeIndex, arcT, aperture,
    physics.bladeCount, physics.radius, dome.radius, physics.twistRadians
  );

  // Hide vertex if seam computation returned hidden marker
  if (pos3D.y < -100.0f) {
    float3 meshPos = params.geometry().model_position();
    params.geometry().set_model_position_offset(float3(0, -1000.0f, 0) - meshPos);
    return;
  }

  // Compute tangent for width offset
  float3 posPrev = iris_projection::computeSeamPoint(
    bladeIndex, max(0.0f, arcT - 0.02f), aperture,
    physics.bladeCount, physics.radius, dome.radius, physics.twistRadians
  );
  float3 posNext = iris_projection::computeSeamPoint(
    bladeIndex, min(1.0f, arcT + 0.02f), aperture,
    physics.bladeCount, physics.radius, dome.radius, physics.twistRadians
  );

  // Handle edge cases where neighbors are hidden
  if (posPrev.y < -100.0f) posPrev = pos3D;
  if (posNext.y < -100.0f) posNext = pos3D;

  // Compute tangent along the seam curve
  float3 tangentDir = posNext - posPrev;
  float tangentLen = length(tangentDir);

  // Normal is always outward from dome center
  float3 normal = normalize(pos3D);

  // Binormal: perpendicular to both normal and tangent, lying on dome surface
  float3 binormal;
  if (tangentLen < 0.0001f) {
    // Degenerate case: no valid tangent, use arbitrary perpendicular
    binormal = normalize(cross(normal, float3(0, 1, 0)));
    if (length(binormal) < 0.001f) {
      binormal = normalize(cross(normal, float3(1, 0, 0)));
    }
  } else {
    float3 tangent = tangentDir / tangentLen;
    binormal = cross(normal, tangent);
    float binormalLen = length(binormal);
    if (binormalLen < 0.001f) {
      // Tangent nearly parallel to normal, use arbitrary perpendicular
      binormal = normalize(cross(normal, float3(0, 1, 0)));
      if (length(binormal) < 0.001f) {
        binormal = normalize(cross(normal, float3(1, 0, 0)));
      }
    } else {
      binormal = binormal / binormalLen;
    }
  }

  // Apply width offset along binormal (on dome surface)
  float ribbonWidth = 0.003f;
  float3 offsetPos = pos3D + binormal * widthSign * ribbonWidth;

  // Apply outward offset to sit above dome surface
  float3 finalPos = offsetPos + normal * 0.005f;

  // Set position
  float3 meshPos = params.geometry().model_position();
  params.geometry().set_model_position_offset(finalPos - meshPos);
  params.geometry().set_normal(normal);
}

// Color palette for debugging blade boundaries
constant half3 ribbonPalette[] = {
  half3(0.9h, 0.3h, 0.3h),  // Red
  half3(0.9h, 0.6h, 0.2h),  // Orange
  half3(0.9h, 0.9h, 0.3h),  // Yellow
  half3(0.4h, 0.9h, 0.4h),  // Green
  half3(0.3h, 0.7h, 0.9h),  // Cyan
  half3(0.4h, 0.4h, 0.9h),  // Blue
  half3(0.7h, 0.3h, 0.9h),  // Purple
  half3(0.9h, 0.4h, 0.7h),  // Pink
};

// Surface shader: colored by blade index for debugging
[[visible]]
void irisSeamRibbonSurfaceShader(realitykit::surface_parameters params) {
  float2 uv = params.geometry().uv0();
  int bladeIndex = int(floor(uv.y));
  int colorIndex = bladeIndex % 8;

  half3 color = ribbonPalette[colorIndex];
  params.surface().set_base_color(color);
  params.surface().set_metallic(0.0h);
  params.surface().set_roughness(0.3h);
  params.surface().set_specular(0.5h);
  params.surface().set_opacity(1.0h);  // Fully opaque
}
