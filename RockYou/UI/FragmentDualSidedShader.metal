// FragmentDualSidedShader.metal
// RockYou
//
// Surface shader for shatter fragments that shows glass on front faces
// and metal on back faces, using a single mesh instead of two.
//
// custom_parameter: (time, cameraX, cameraY, cameraZ)
//   - time is used by geometry modifier
//   - cameraX, cameraY, cameraZ are the actual camera position
// custom texture: Physics data (same as geometry modifier uses)
// baseColor texture: DPad texture for metal environment mapping

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Texture layout constants (must match geometry modifier)
constant int LOOKUP_TABLE_SIZE = 1024;
constant int FRAGMENTS_PER_ROW = 512;  // Each fragment uses 2 columns for 16-bit precision
constant int TEXTURE_WIDTH = 1024;     // 512 fragments * 2 columns each
constant int HEADER_COL = 3;
constant float MAX_TEXTURE_HEIGHT = 65536.0f;  // Max encodable height (16-bit) for header UV

// Glass appearance (tuned to match dome glass)
constant half3 GLASS_COLOR = half3(0.1h, 0.12h, 0.15h);  // Dark base
constant half GLASS_OPACITY = 0.15h;
constant half GLASS_ROUGHNESS = 0.05h;
constant half GLASS_METALLIC = 0.0h;
constant half GLASS_SPECULAR = 0.8h;

// Metal appearance
constant half METAL_OPACITY = 1.0h;
constant half METAL_ROUGHNESS = 0.15h;
constant half METAL_METALLIC = 0.9h;

// Env map scale - how big the "reflected" dpad appears
constant float ENV_MAP_SCALE = 2.0f;

[[visible]]
void fragmentDualSidedShader(realitykit::surface_parameters params) {
  constexpr sampler texSampler(address::clamp_to_edge, filter::linear);
  constexpr sampler dataSampler(address::clamp_to_edge, filter::nearest);

  // Get custom parameters: (time, cameraX, cameraY, cameraZ)
  float4 customData = params.uniforms().custom_parameter();
  float time = customData.x;
  float3 cameraPos = float3(customData.y, customData.z, customData.w);

  // Get physics data texture
  auto dataTexture = params.textures().custom();

  // Read textureHeight from header (row 0, col 3)
  float2 headerUV = float2((float(HEADER_COL) + 0.5f) / float(TEXTURE_WIDTH),
                           0.5f / MAX_TEXTURE_HEIGHT);
  float4 headerData = float4(dataTexture.sample(dataSampler, headerUV));
  float textureHeight = headerData.r * 256.0f * 255.0f + headerData.g * 255.0f;

  // Get fragment index from UV (same encoding as geometry modifier)
  float2 uv = params.geometry().uv0();
  int fragmentIndex = int(floor(uv.x));

  // Read fragment center from texture (16-bit precision, 2 columns per fragment)
  int fragInRow = fragmentIndex % FRAGMENTS_PER_ROW;
  int fragRow = LOOKUP_TABLE_SIZE + (fragmentIndex / FRAGMENTS_PER_ROW);
  int col0 = fragInRow * 2;
  int col1 = fragInRow * 2 + 1;

  float2 fragUV0 = float2((float(col0) + 0.5f) / float(TEXTURE_WIDTH),
                          (float(fragRow) + 0.5f) / textureHeight);
  float2 fragUV1 = float2((float(col1) + 0.5f) / float(TEXTURE_WIDTH),
                          (float(fragRow) + 0.5f) / textureHeight);
  float4 fragData0 = float4(dataTexture.sample(dataSampler, fragUV0));
  float4 fragData1 = float4(dataTexture.sample(dataSampler, fragUV1));

  // Decode fragment data with 16-bit precision
  float spawnTime = fragData0.r * 10.0f;
  float x16 = fragData0.g * 255.0f * 256.0f + fragData0.b * 255.0f;
  float y16 = fragData0.a * 255.0f * 256.0f + fragData1.r * 255.0f;
  float z16 = fragData1.g * 255.0f * 256.0f + fragData1.b * 255.0f;
  float3 center = float3(x16, y16, z16) / 65535.0f * 2.0f - 1.0f;

  // Compute elapsed time and approximate world position
  float elapsed = max(0.0f, time - spawnTime);

  // Simple physics approximation (matches geometry modifier)
  // We don't have exact velocity/gravity per fragment here, so use center + fall estimate
  float avgGravity = 0.5f;  // Approximate
  float3 actualWorldPos = center + float3(0, -0.5f * avgGravity * elapsed * elapsed, 0);

  // Get face normal (rotated by geometry modifier)
  float3 normal = params.geometry().normal();

  // Compute view direction using ACTUAL world position
  float3 viewDir = normalize(cameraPos - actualWorldPos);

  // Front face = normal facing toward camera (positive dot product)
  bool isFrontFace = dot(normal, viewDir) > 0.0f;

  // Flip normal for back faces so both sides receive proper lighting
  // NOTE: Don't call set_normal() - causes checkerboard with .lit lighting
  float3 N = isFrontFace ? normal : -normal;

  if (isFrontFace) {
    // Glass appearance with RED tint for debug
    half3 tintedGlass = GLASS_COLOR + half3(0.3h, 0.0h, 0.0h);  // Add red
    params.surface().set_base_color(tintedGlass);
    params.surface().set_opacity(GLASS_OPACITY);
    params.surface().set_roughness(GLASS_ROUGHNESS);
    params.surface().set_metallic(GLASS_METALLIC);
    params.surface().set_specular(GLASS_SPECULAR);
  } else {
    // Metal appearance with BLUE tint for debug
    float2 envUV = float2(
      actualWorldPos.x * ENV_MAP_SCALE + 0.5f,
      actualWorldPos.z * ENV_MAP_SCALE + 0.5f
    );
    half4 envSample = params.textures().base_color().sample(texSampler, envUV);
    half3 silverBase = half3(0.75h, 0.75h, 0.8h);
    half3 metalColor = mix(silverBase, envSample.rgb, 0.6h);
    half3 tintedMetal = metalColor + half3(0.0h, 0.0h, 0.3h);  // Add blue

    params.surface().set_base_color(tintedMetal);
    params.surface().set_opacity(METAL_OPACITY);
    params.surface().set_roughness(METAL_ROUGHNESS);
    params.surface().set_metallic(METAL_METALLIC);
  }
}
