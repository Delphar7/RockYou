// TextureParams.h
// RockYou
//
// Texture parameter reader for GPU shaders.
//
// Format: Each texture column stores 2 data bytes + 2 sentinel bytes:
//   [data, data, 0xDE, 0xED]
//
// Virtual byte N maps to:
//   Column = N / 2
//   Channel = N % 2 (0 = R, 1 = G)
//
// The sentinel bytes keep alpha non-zero, preventing ASTC texture compression
// on iOS A-series GPUs from corrupting parameter data.
//
// 16-bit and 32-bit reads require even byte offsets, enforced via static_assert.

#pragma once

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Virtual byte offset constants — must match Swift TextureParam enum
// =============================================================================

namespace tex_param {
  enum : int {
    // Shared dome params (all algorithms)
    RADIUS = 0,           // float16 [0.0, 2.0]
    LAT_SEGMENTS = 2,     // int16
    LON_SEGMENTS = 4,     // int16
    WAVE_SPEED = 6,       // float16 [0.0, 20.0]
    WAVE_ORIGIN_X = 8,    // float16 [-2.0, 2.0]
    WAVE_ORIGIN_Y = 10,   // float16 [-2.0, 2.0]
    WAVE_ORIGIN_Z = 12,   // float16 [-2.0, 2.0]
    WAVE_ENABLED = 14,    // int16

    // Algorithm identification
    ALGORITHM_ID = 16,    // int16
    CANNON_POWER = 18,    // float16 [0.0, 5.0]

    // Physics config (explode/confetti/ripple)
    BASE_GRAVITY = 20,    // float16 [0.0, 2.0]
    GRAVITY_MIN = 22,     // float16 [0.0, 2.0]
    GRAVITY_MAX = 24,     // float16 [0.0, 2.0]
    SPIN_RATE_MIN = 26,   // float16 [0.0, 20.0]
    SPIN_RATE_MAX = 28,   // float16 [0.0, 20.0]
    BASE_SPEED = 30,      // float16 [-2.0, 2.0]
    SPREAD_ANGLE = 32,    // float16 [0.0, 2.0]
    UPWARD_BIAS = 34,     // float16 [-2.0, 2.0]

    // Ripple-specific
    WAVE_FREQUENCY = 36,  // float16 [1.0, 10.0]
    WAVE_AMPLITUDE = 38,  // float16 [0.0, 0.2]
    RIPPLE_SPEED = 40,    // float16 [0.0, 2.0]

    // Iris-specific
    BLADE_COUNT = 42,     // int16
    OPEN_DURATION = 44,   // float16 [0.1, 10.0]
    TILT = 46,            // float16 [0.0, π/2]
    ELEVATION = 48,       // float16 [0.0, π/4]
  };
}

// =============================================================================
// Reader
// =============================================================================

struct TextureParamReader {
  texture2d<half, access::sample> tex;
  float invWidth;
  float invHeight;

  /// Sample a single texture column (R=data0, G=data1, B=sentinel, A=sentinel).
  inline float4 sampleColumn(int col) const {
    float2 uv = float2((float(col) + 0.5f) * invWidth, 0.5f * invHeight);
    constexpr sampler s(address::clamp_to_edge, filter::nearest);
    return float4(tex.sample(s, uv));
  }

  /// Read a single byte at any virtual offset.
  inline int readByte(int offset) const {
    int col = offset / 2;
    int ch = offset % 2;
    float4 raw = sampleColumn(col);
    return int(round((ch == 0 ? raw.r : raw.g) * 255.0f));
  }

  /// Read 16-bit integer at even virtual offset (compile-time enforced).
  template<int Offset>
  inline int readInt16() const {
    static_assert(Offset >= 0, "Offset must be non-negative");
    static_assert(Offset % 2 == 0, "16-bit reads must be at even byte offsets");
    float4 raw = sampleColumn(Offset / 2);
    int high = int(round(raw.r * 255.0f));
    int low = int(round(raw.g * 255.0f));
    return high * 256 + low;
  }

  /// Read float encoded as 16-bit in [minVal, maxVal] at even virtual offset.
  template<int Offset>
  inline float readFloat16(float minVal, float maxVal) const {
    return float(readInt16<Offset>()) / 65535.0f * (maxVal - minVal) + minVal;
  }

  /// Read 32-bit integer at even virtual offset (spans 2 columns).
  template<int Offset>
  inline int readInt32() const {
    static_assert(Offset >= 0, "Offset must be non-negative");
    static_assert(Offset % 2 == 0, "32-bit reads must be at even byte offsets");
    return readInt16<Offset>() * 65536 + readInt16<Offset + 2>();
  }
};
