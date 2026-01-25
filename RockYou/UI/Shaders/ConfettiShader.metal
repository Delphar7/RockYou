// ConfettiShader.metal
// RockYou
//
// Confetti algorithm shader: Fragments flutter down like confetti.
// Exports both geometry modifier and visibility kernel.

#include "FragmentShaderScaffold.h"
#include "Algorithms/ConfettiAlgorithm.h"

FRAGMENT_GEOMETRY_MODIFIER(confetti, confetti)
FRAGMENT_VISIBILITY_KERNEL(confetti, confetti)

// Bright metallic palette - shiny wrapping paper vibes
constant half3 confettiPalette[] = {
  half3(1.0h, 0.3h, 0.3h),   // Bright Red
  half3(0.3h, 1.0h, 0.3h),   // Bright Green
  half3(0.4h, 0.6h, 1.0h),   // Bright Blue
  half3(1.0h, 0.9h, 0.2h),   // Bright Gold
  half3(1.0h, 0.3h, 1.0h),   // Bright Magenta
  half3(0.2h, 1.0h, 1.0h),   // Bright Cyan
  half3(1.0h, 0.6h, 0.1h),   // Bright Orange
  half3(1.0h, 1.0h, 1.0h),   // Bright Silver/White
};

// Confetti surface shader - colorful shiny metals like wrapping paper
[[visible]]
void confettiSurfaceShader(realitykit::surface_parameters params) {
  float2 uv = params.geometry().uv0();
  int fragmentIndex = int(round(uv.x));
  bool backFacing = uv.y > 0.5f;

  // Use stable_random for good randomization (different seed than physics)
  int colorIdx = int(fragment_math::stable_random(fragmentIndex, 9973) * 8.0f);
  half3 color = confettiPalette[colorIdx];

  if (backFacing) {
    // Back side: darker, less shiny (like paper backing on foil)
    params.surface().set_base_color(color * 0.3h);
    params.surface().set_opacity(1.0h);
    params.surface().set_roughness(0.6h);   // Matte
    params.surface().set_metallic(0.1h);    // Not metallic
    params.surface().set_specular(0.1h);
  } else {
    // Front side: bright shiny metal
    params.surface().set_base_color(color);
    params.surface().set_opacity(1.0h);
    params.surface().set_roughness(0.15h);
    params.surface().set_metallic(0.9h);
    params.surface().set_specular(0.5h);
  }
}
