// FragmentSurfaceShader.metal
// RockYou
//
// Shared surface shader for all dome collapse algorithms.
// Glass on back faces, metal on front faces.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>

using namespace metal;

[[visible]]
void fragmentSurfaceShader(realitykit::surface_parameters params) {
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
