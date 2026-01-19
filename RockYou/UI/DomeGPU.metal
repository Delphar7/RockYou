// DomeGPU.metal
// RockYou
//
// Metal compute shader for GPU-accelerated iris mask generation.
// Port of DomeIrisAnimation.swift math to Metal.

#include <metal_stdlib>
using namespace metal;

// ------------------------------------------------------------
// Config uniforms (mirrors DomeIrisConfig)
// ------------------------------------------------------------

struct IrisConfig {
  float rotMax;
  float edgeSoftness;
  float seamWidth;
  float seamSoftness;
  float seamPivotRadius;
  float seamBladeRotMax;
  float retractExtraBladeRotMax;
  float seamEdgeInnerRadius;
  float seamEdgeOuterRadius;
  float seamArcSagitta;
  float unlockEnd;
  int bladeCount;
  // Glass appearance
  float glassColorR;
  float glassColorG;
  float glassColorB;
  float glassAlpha;
  float seamColorR;
  float seamColorG;
  float seamColorB;
  float seamAlpha;
};

struct IrisParams {
  float t;
  int width;
  int height;
  int flipY;
};

// ------------------------------------------------------------
// Precomputed frame values (mirrors IrisFrame)
// ------------------------------------------------------------

struct IrisFrame {
  float uOpen;
  float uRetract;
  int N;
  float rot;
  float deltaOpen;
  float deltaRetract;
  float delta;
  float rp;
  float rInner;
  float rOuter;
  float rOuterEff;
  float sagitta;
  float2 pivotLocal;
  float2 poutOpenLocal;
  float phiSpan;
  float sector;
  float miterAngle;
  float miterPush;
};

// ------------------------------------------------------------
// Math helpers
// ------------------------------------------------------------

inline float clamp01(float x) {
  return clamp(x, 0.0f, 1.0f);
}

inline float smoothstep01(float t) {
  float x = clamp01(t);
  return x * x * (3.0f - 2.0f * x);
}

inline float smoothstepEdge(float edge0, float edge1, float x) {
  float denom = max(1e-6f, edge1 - edge0);
  float t = clamp01((x - edge0) / denom);
  return t * t * (3.0f - 2.0f * t);
}

inline float2 rotate2d(float2 p, float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

inline float2 rotateAround(float2 p, float2 center, float angle) {
  return rotate2d(p - center, angle) + center;
}

inline float wrapAnglePi(float a) {
  float twoPi = 2.0f * M_PI_F;
  float x = fmod(a + M_PI_F, twoPi);
  if (x < 0.0f) x += twoPi;
  return x - M_PI_F;
}

inline float edgeYExtended(float qx, float rInner, float rOuterEff, float sagitta) {
  float denom = max(1e-6f, rOuterEff - rInner);
  float t = (qx - rInner) / denom;

  if (t <= 1.0f) {
    float tc = max(0.0f, t);
    return sagitta * sin(tc * M_PI_F);
  } else {
    float slope = -sagitta * M_PI_F;
    return slope * (t - 1.0f);
  }
}

inline float tUnlock(float t, float unlockEnd) {
  return clamp01(t / max(1e-6f, unlockEnd));
}

inline float tRetract(float t, float unlockEnd) {
  float denom = max(1e-6f, 1.0f - unlockEnd);
  return clamp01((t - unlockEnd) / denom);
}

// ------------------------------------------------------------
// Frame computation
// ------------------------------------------------------------

inline IrisFrame makeFrame(float t, constant IrisConfig& cfg) {
  IrisFrame f;

  f.uOpen = smoothstep01(tUnlock(t, cfg.unlockEnd));
  f.uRetract = smoothstep01(tRetract(t, cfg.unlockEnd));

  f.N = max(3, cfg.bladeCount);
  f.rp = clamp01(cfg.seamPivotRadius);
  f.rInner = cfg.seamEdgeInnerRadius;
  f.rOuter = cfg.seamEdgeOuterRadius;
  f.rOuterEff = f.rOuter;
  f.sagitta = cfg.seamArcSagitta;

  f.rot = -cfg.rotMax * (1.0f - f.uOpen);
  f.deltaOpen = cfg.seamBladeRotMax * f.uOpen;
  f.deltaRetract = cfg.retractExtraBladeRotMax * f.uRetract;
  f.delta = f.deltaOpen + f.deltaRetract;

  f.pivotLocal = float2(f.rp, 0.0f);

  // Pout/Pin positions in blade-local space at end-of-open
  f.poutOpenLocal = rotateAround(float2(f.rOuter, 0.0f), f.pivotLocal, f.deltaOpen);
  float2 pinOpenLocal = rotateAround(float2(f.rInner, 0.0f), f.pivotLocal, f.deltaOpen);

  // Hinge target calculation
  float2 v0 = pinOpenLocal - f.poutOpenLocal;
  float2 vTarget = -f.poutOpenLocal;
  float a0 = atan2(v0.y, v0.x);
  float aT = atan2(vTarget.y, vTarget.x);
  f.phiSpan = wrapAnglePi(aT - a0);

  f.sector = (2.0f * M_PI_F) / float(f.N);

  float baseMiterAngle = M_PI_F / float(f.N) * 1.33f;
  f.miterAngle = baseMiterAngle + (M_PI_F / 2.0f - baseMiterAngle) * f.uOpen;
  f.miterPush = 0.015f * (1.0f - f.uOpen);

  return f;
}

// ------------------------------------------------------------
// Blade evaluation
// ------------------------------------------------------------

struct BladeEval {
  float signedDist;
  float edgeDist;
  bool passedInnerGate;
  bool passedOuterGate;
};

inline BladeEval evalBlade(float2 p, int bladeIndex, IrisFrame f) {
  BladeEval e;

  float alpha = f.sector * float(bladeIndex) + f.rot;

  // 1) Rotate world point into blade-i base frame
  float2 q = rotate2d(p, -alpha);

  // 2) During retract, undo hinge rotation about pinned outer endpoint
  if (f.uRetract > 0.0f) {
    float phi = f.phiSpan * f.uRetract;
    q = rotateAround(q, f.poutOpenLocal, phi);
  }

  // 3) Undo opening motion
  q = rotateAround(q, f.pivotLocal, -f.deltaOpen);

  // 4) Gate by outer radius
  e.passedOuterGate = (q.x <= f.rOuterEff);

  // 5) Compute curved edge Y-position
  float edgeY = edgeYExtended(q.x, f.rInner, f.rOuterEff, f.sagitta);

  // 6) Miter the inner end
  float yOffset = q.y - edgeY;
  float rInnerMitered = (f.rInner - f.miterPush) - yOffset / tan(f.miterAngle);
  e.passedInnerGate = (q.x >= rInnerMitered);

  // 7) Signed distance
  if (e.passedInnerGate) {
    e.signedDist = q.y - edgeY;
  } else {
    e.signedDist = q.y;
  }

  // 8) Distance to edge curve (for seams)
  e.edgeDist = abs(q.y - edgeY);

  return e;
}

// ------------------------------------------------------------
// Mask computation
// ------------------------------------------------------------

inline float computeMask(float2 p, IrisFrame f, constant IrisConfig& cfg) {
  float minSignedDist = 1e10f;

  for (int i = 0; i < f.N; i++) {
    BladeEval e = evalBlade(p, i, f);
    minSignedDist = min(minSignedDist, e.signedDist);
  }

  float apertureInset = cfg.seamWidth * 0.5f;
  return smoothstepEdge(-cfg.edgeSoftness, cfg.edgeSoftness, minSignedDist - apertureInset);
}

// ------------------------------------------------------------
// Seam mask computation
// ------------------------------------------------------------

inline int positiveMod(int a, int n) {
  int r = a % n;
  return r < 0 ? (r + n) : r;
}

inline int nearestSectorIndex(float theta, int N) {
  float sector = (2.0f * M_PI_F) / float(N);
  float q = theta / sector;
  int k = int(round(q));
  return positiveMod(k, N);
}

inline float computeSeamMask(float2 p, IrisFrame f, constant IrisConfig& cfg) {
  if (cfg.seamWidth <= 0.0f) return 0.0f;

  bool restrictOwnership = (f.uOpen > 0.92f);
  float theta = atan2(p.y, p.x);
  float thetaLocal = wrapAnglePi(theta - f.rot);
  int iCenter = nearestSectorIndex(thetaLocal, f.N);

  float seam = 0.0f;

  if (restrictOwnership) {
    // Evaluate owning sector and immediate neighbors
    for (int di = -1; di <= 1; di++) {
      int i = positiveMod(iCenter + di, f.N);
      BladeEval e = evalBlade(p, i, f);
      if (!e.passedOuterGate) continue;
      if (!e.passedInnerGate) continue;
      float s = 1.0f - smoothstepEdge(cfg.seamWidth, cfg.seamWidth + cfg.seamSoftness, e.edgeDist);
      seam = max(seam, s);
    }
  } else {
    for (int i = 0; i < f.N; i++) {
      BladeEval e = evalBlade(p, i, f);
      if (!e.passedOuterGate) continue;
      if (!e.passedInnerGate) continue;
      float s = 1.0f - smoothstepEdge(cfg.seamWidth, cfg.seamWidth + cfg.seamSoftness, e.edgeDist);
      seam = max(seam, s);
    }
  }

  return seam;
}

// ------------------------------------------------------------
// Main compute kernel
// ------------------------------------------------------------

kernel void irisGlassMaskKernel(
  texture2d<float, access::write> outTex [[texture(0)]],
  constant IrisConfig& cfg [[buffer(0)]],
  constant IrisParams& params [[buffer(1)]],
  uint2 gid [[thread_position_in_grid]]
) {
  int width = params.width;
  int height = params.height;

  if (int(gid.x) >= width || int(gid.y) >= height) return;

  // UV coordinates [-1, 1]
  float u = (float(gid.x) + 0.5f) / float(width);
  float v = (float(gid.y) + 0.5f) / float(height);

  float py = params.flipY ? ((1.0f - v) * 2.0f - 1.0f) : (v * 2.0f - 1.0f);
  float px = u * 2.0f - 1.0f;

  float2 p = float2(px, py);
  float r = min(1.0f, length(p));

  // Compute frame once per pixel (could optimize by computing once per dispatch)
  IrisFrame frame = makeFrame(params.t, cfg);

  // Mask value: 0 = covered, 1 = open
  float m = computeMask(p, frame, cfg);

  // Seam intensity
  float seam = computeSeamMask(p, frame, cfg);

  // Base glass: 0 where open, glass opacity where covered
  float glassA = cfg.glassAlpha * (1.0f - m);

  // Seams: white opaque, only on covered areas
  float seamIntensity = seam * (1.0f - m);

  // Blend between glass and seam based on seam intensity
  float blendedR = cfg.glassColorR * (1.0f - seamIntensity) + cfg.seamColorR * seamIntensity;
  float blendedG = cfg.glassColorG * (1.0f - seamIntensity) + cfg.seamColorG * seamIntensity;
  float blendedB = cfg.glassColorB * (1.0f - seamIntensity) + cfg.seamColorB * seamIntensity;
  float blendedA = glassA * (1.0f - seamIntensity) + cfg.seamAlpha * seamIntensity;

  // Outside unit disc: fully transparent
  float finalAlpha = (r > 1.0f) ? 0.0f : blendedA;

  // Premultiplied RGBA (note: BGRA format for RealityKit compatibility)
  float4 color = float4(
    blendedB * finalAlpha / 255.0f,  // B
    blendedG * finalAlpha / 255.0f,  // G
    blendedR * finalAlpha / 255.0f,  // R
    finalAlpha                        // A
  );

  outTex.write(color, gid);
}
