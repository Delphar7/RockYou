// DomeSurfaceShader.metal
// RockYou
//
// Surface shader for CustomMaterial that composites DPad textures by ray-tracing
// through the dome to a virtual backdrop plane:
// - Through aperture (maskAlpha=0): show regular DPad texture
// - Through glass (maskAlpha>0): inverted blend ratio (thin glass = more refraction)
// - The blend artifact between misaligned textures creates distortion for thicker glass
//
// custom_parameter: (cameraX, cameraY, cameraZ, backdropSize)
// baseColor texture: DPad-Regular.png
// emissiveColor texture: DPad-Refracted.png
// custom texture: iris glass mask

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Tuning constants
constant half REFRACT_BLEND_RATIO = 1.0h;  // 0 = all Regular, 1 = full Refracted blend

// Surface shader entry point
[[visible]]
void domeSurfaceShader(realitykit::surface_parameters params) {
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);

  // Get custom parameters: camera position (xyz) + backdrop size (w)
  float4 customData = params.uniforms().custom_parameter();
  float3 cameraPos = customData.xyz;
  float backdropSize = customData.w;

  // Backdrop plane Y position (slightly below dome origin)
  const float BACKDROP_Y = -0.01f;

  // Fragment world position
  float3 fragPos = (float3)params.geometry().world_position();

  // Ray from camera through fragment
  float3 rayDir = normalize(fragPos - cameraPos);

  // Ray-plane intersection: find where ray hits backdrop plane at y = BACKDROP_Y
  // Solve: fragPos.y + t * rayDir.y = BACKDROP_Y
  float t = (BACKDROP_Y - fragPos.y) / rayDir.y;
  float3 hitPoint = fragPos + t * rayDir;

  // Convert hit point to UV [0,1] (backdrop centered at origin on XZ plane)
  float2 dpadUV = float2(
    hitPoint.x / backdropSize + 0.5f,
    hitPoint.z / backdropSize + 0.5f
  );

  // Check if UV is within valid DPad texture bounds
  bool insideDPad = (dpadUV.x >= 0.0f && dpadUV.x <= 1.0f &&
                     dpadUV.y >= 0.0f && dpadUV.y <= 1.0f);

  // Sample iris mask from custom texture (dome UV mapping)
  // Mask contains: RGB = glass tint + white seams (premultiplied), A = opacity
  float2 domeUV = params.geometry().uv0();
  half4 maskTex = params.textures().custom().sample(texSampler, domeUV);
  half maskAlpha = maskTex.a;

  half3 finalBaseColor;   // Glass surface (lit, receives specular)
  half3 finalEmissive;    // DPad content seen through glass (unlit)
  half finalAlpha;

  if (insideDPad) {
    // Inside DPad bounds: sample and composite DPad textures
    half4 regularTex = params.textures().base_color().sample(texSampler, dpadUV);
    half4 refractedTex = params.textures().emissive_color().sample(texSampler, dpadUV);

    // Blend DPad textures: Regular for aperture, inverted ratio for glass
    // (thin glass shows more pre-baked refraction, thicker glass lets blend artifact create distortion)
    const half GLASS_THRESHOLD = 0.01h;
    half blendFactor = (maskAlpha > GLASS_THRESHOLD) ? (1.0h - maskAlpha) : 0.0h;
    half3 dpadColor = mix(regularTex.rgb, refractedTex.rgb, blendFactor);
    half dpadAlpha = regularTex.a;  // Regular defines DPad shape boundary

    // If DPad texture is transparent at this point (outside the circular DPad),
    // treat it as if we're outside the DPad entirely
    if (dpadAlpha < 0.01h) {
      // Transparent DPad area: show only glass/seams if present, else fully transparent
      finalBaseColor = maskAlpha > 0.01h ? maskTex.rgb / maskAlpha : half3(0.0h);
      finalEmissive = half3(0.0h);
      finalAlpha = maskAlpha;
    } else {
      // Solid DPad area: glass surface + DPad seen through

      // Unpremultiply mask color to detect seams
      half3 maskColor = maskAlpha > 0.01h ? maskTex.rgb / maskAlpha : half3(0.0h);

      // Detect seam intensity by brightness (glass is dark ~0.1, seams are white ~1.0)
      half luminance = dot(maskColor, half3(0.299h, 0.587h, 0.114h));
      half seamIntensity = saturate((luminance - 0.15h) / 0.85h);

      // Tint seams with a touch of underlying DPad color (20% tint)
      half3 tintedSeamColor = mix(maskColor, maskColor * (half3(0.8h) + dpadColor * 0.2h), seamIntensity);

      // Glass surface: base_color (lit, receives specular from clearcoat)
      finalBaseColor = tintedSeamColor;

      // DPad seen through glass: emissive (unlit backdrop)
      // Boost to compensate for opacity reduction (0.3) if RealityKit scales emissive by opacity
      finalEmissive = dpadColor * 3.5h;

      // Alpha: standard over composite, seams stay opaque
      finalAlpha = mix(
        maskAlpha + dpadAlpha * (1.0h - maskAlpha),  // Normal blend for glass
        max(maskAlpha, dpadAlpha),                    // Seams stay opaque
        seamIntensity
      );
    }
  } else {
    // Outside DPad UV bounds: show only glass/seams, no DPad
    finalBaseColor = maskAlpha > 0.01h ? maskTex.rgb / maskAlpha : half3(0.0h);
    finalEmissive = half3(0.0h);
    finalAlpha = maskAlpha;
  }

  params.surface().set_base_color(finalBaseColor);
  params.surface().set_emissive_color(finalEmissive);
  // Scale down opacity for clearer glass (was 1:1 with finalAlpha)
  params.surface().set_opacity(max(finalAlpha * 0.3h, 0.001h));

  // Glass material properties fade in with mask alpha
  params.surface().set_metallic(0.0h);
  params.surface().set_roughness(mix(1.0h, 0.02h, maskAlpha));   // Lower = shinier
  params.surface().set_clearcoat(0.7h * maskAlpha);              // Higher = more reflective
  params.surface().set_clearcoat_roughness(0.01h * maskAlpha);   // Lower = tighter highlights
}
