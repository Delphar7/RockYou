// DomeGPU.swift
// RockYou
//
// GPU-accelerated iris mask generation using Metal compute shaders.
// Alternative to CPU-based DomeIrisMaskRenderer.makeGlassMaskImage().

import CoreGraphics
import Foundation
import Metal
import simd

/// GPU-accelerated dome iris mask renderer.
enum DomeGPURenderer {

  // MARK: - Metal Uniform Structs (must match DomeGPU.metal)

  /// Mirrors IrisConfig in Metal shader
  struct IrisConfigUniforms {
    var rotMax: Float
    var edgeSoftness: Float
    var seamWidth: Float
    var seamSoftness: Float
    var seamPivotRadius: Float
    var seamBladeRotMax: Float
    var retractExtraBladeRotMax: Float
    var seamEdgeInnerRadius: Float
    var seamEdgeOuterRadius: Float
    var seamArcSagitta: Float
    var unlockEnd: Float
    var bladeCount: Int32
    // Glass appearance
    var glassColorR: Float
    var glassColorG: Float
    var glassColorB: Float
    var glassAlpha: Float
    var seamColorR: Float
    var seamColorG: Float
    var seamColorB: Float
    var seamAlpha: Float
  }

  /// Mirrors IrisParams in Metal shader
  struct IrisParamsUniforms {
    var t: Float
    var width: Int32
    var height: Int32
    var flipY: Int32
  }

  // MARK: - Pipeline State Cache

  private static var cachedDevice: MTLDevice?
  private static var cachedPipeline: MTLComputePipelineState?
  private static var cachedQueue: MTLCommandQueue?

  /// Initialize or return cached Metal pipeline.
  private static func getPipeline() throws -> (MTLDevice, MTLComputePipelineState, MTLCommandQueue) {
    if let device = cachedDevice, let pipeline = cachedPipeline, let queue = cachedQueue {
      return (device, pipeline, queue)
    }

    guard let device = MTLCreateSystemDefaultDevice() else {
      throw DomeGPUError.noMetalDevice
    }

    // Try to load from default library (compiled .metal file)
    // Falls back to inline source if .metal file not in project
    let library: MTLLibrary
    if let defaultLib = device.makeDefaultLibrary(),
      defaultLib.functionNames.contains("irisGlassMaskKernel")
    {
      library = defaultLib
    } else {
      // Fallback: compile from inline source
      library = try device.makeLibrary(source: metalSource, options: nil)
    }

    guard let function = library.makeFunction(name: "irisGlassMaskKernel") else {
      throw DomeGPUError.missingKernelFunction
    }

    let pipeline = try device.makeComputePipelineState(function: function)

    guard let queue = device.makeCommandQueue() else {
      throw DomeGPUError.failedToCreateCommandQueue
    }

    cachedDevice = device
    cachedPipeline = pipeline
    cachedQueue = queue

    return (device, pipeline, queue)
  }

  // MARK: - Public API

  /// Generate glass mask image using GPU compute shader.
  /// - Parameters:
  ///   - size: Texture size (width = height)
  ///   - t: Animation progress 0..1
  ///   - bladeCount: Number of iris blades
  ///   - config: Iris configuration
  ///   - flipY: Flip Y axis for texture orientation
  /// - Returns: CGImage with RGBA glass mask, or nil on failure
  static func makeGlassMaskImage(
    size: Int,
    t: Float,
    bladeCount: Int,
    config: DomeIrisConfig,
    flipY: Bool = true
  ) -> CGImage? {
    do {
      return try makeGlassMaskImageThrowing(
        size: size, t: t, bladeCount: bladeCount, config: config, flipY: flipY)
    } catch {
      Log.error("DomeGPU", "GPU mask generation failed: \(error)")
      return nil
    }
  }

  /// Throwing version of makeGlassMaskImage for detailed error handling.
  static func makeGlassMaskImageThrowing(
    size: Int,
    t: Float,
    bladeCount: Int,
    config: DomeIrisConfig,
    flipY: Bool = true
  ) throws -> CGImage {
    let (device, pipeline, queue) = try getPipeline()

    let width = max(1, size)
    let height = max(1, size)

    // Create output texture
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    desc.storageMode = .shared

    guard let outTex = device.makeTexture(descriptor: desc) else {
      throw DomeGPUError.failedToCreateTexture
    }

    // Prepare uniforms
    var configUniforms = IrisConfigUniforms(
      rotMax: config.rotMax,
      edgeSoftness: config.edgeSoftness,
      seamWidth: config.seamWidth,
      seamSoftness: config.seamSoftness,
      seamPivotRadius: config.seamPivotRadius,
      seamBladeRotMax: config.seamBladeRotMax,
      retractExtraBladeRotMax: config.retractExtraBladeRotMax,
      seamEdgeInnerRadius: config.seamEdgeInnerRadius,
      seamEdgeOuterRadius: config.seamEdgeOuterRadius,
      seamArcSagitta: config.seamArcSagitta,
      unlockEnd: config.unlockEnd,
      bladeCount: Int32(bladeCount),
      glassColorR: DomeIrisMaskRenderer.glassColor.r,
      glassColorG: DomeIrisMaskRenderer.glassColor.g,
      glassColorB: DomeIrisMaskRenderer.glassColor.b,
      glassAlpha: DomeIrisMaskRenderer.glassAlpha,
      seamColorR: DomeIrisMaskRenderer.seamColor.r,
      seamColorG: DomeIrisMaskRenderer.seamColor.g,
      seamColorB: DomeIrisMaskRenderer.seamColor.b,
      seamAlpha: DomeIrisMaskRenderer.seamAlpha
    )

    var paramsUniforms = IrisParamsUniforms(
      t: t,
      width: Int32(width),
      height: Int32(height),
      flipY: flipY ? 1 : 0
    )

    // Encode compute command
    guard let commandBuffer = queue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw DomeGPUError.failedToCreateCommandBuffer
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(outTex, index: 0)
    encoder.setBytes(&configUniforms, length: MemoryLayout<IrisConfigUniforms>.stride, index: 0)
    encoder.setBytes(&paramsUniforms, length: MemoryLayout<IrisParamsUniforms>.stride, index: 1)

    // Dispatch threads
    let w = pipeline.threadExecutionWidth
    let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
    let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
    let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
    encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)

    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // Convert texture to CGImage
    return try cgImageFromBGRA8Texture(outTex)
  }

  // MARK: - Texture to CGImage

  private static func cgImageFromBGRA8Texture(_ tex: MTLTexture) throws -> CGImage {
    let width = tex.width
    let height = tex.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: bytesPerRow * height)

    tex.getBytes(
      &data,
      bytesPerRow: bytesPerRow,
      from: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0
    )

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))

    guard let provider = CGDataProvider(data: Data(data) as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    else {
      throw DomeGPUError.failedToCreateCGImage
    }

    return image
  }

  // MARK: - Errors

  enum DomeGPUError: Error, LocalizedError {
    case noMetalDevice
    case missingKernelFunction
    case failedToCreateCommandQueue
    case failedToCreateTexture
    case failedToCreateCommandBuffer
    case failedToCreateCGImage

    var errorDescription: String? {
      switch self {
      case .noMetalDevice: return "No Metal device available"
      case .missingKernelFunction: return "Missing irisGlassMaskKernel function"
      case .failedToCreateCommandQueue: return "Failed to create Metal command queue"
      case .failedToCreateTexture: return "Failed to create output texture"
      case .failedToCreateCommandBuffer: return "Failed to create command buffer/encoder"
      case .failedToCreateCGImage: return "Failed to create CGImage from texture"
      }
    }
  }

  // MARK: - Inline Metal Source (fallback if .metal file not compiled)

  private static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

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

    inline float clamp01(float x) { return clamp(x, 0.0f, 1.0f); }

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
      f.poutOpenLocal = rotateAround(float2(f.rOuter, 0.0f), f.pivotLocal, f.deltaOpen);
      float2 pinOpenLocal = rotateAround(float2(f.rInner, 0.0f), f.pivotLocal, f.deltaOpen);
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

    struct BladeEval {
      float signedDist;
      float edgeDist;
      bool passedInnerGate;
      bool passedOuterGate;
    };

    inline BladeEval evalBlade(float2 p, int bladeIndex, IrisFrame f) {
      BladeEval e;
      float alpha = f.sector * float(bladeIndex) + f.rot;
      float2 q = rotate2d(p, -alpha);
      if (f.uRetract > 0.0f) {
        float phi = f.phiSpan * f.uRetract;
        q = rotateAround(q, f.poutOpenLocal, phi);
      }
      q = rotateAround(q, f.pivotLocal, -f.deltaOpen);
      e.passedOuterGate = (q.x <= f.rOuterEff);
      float edgeY = edgeYExtended(q.x, f.rInner, f.rOuterEff, f.sagitta);
      float yOffset = q.y - edgeY;
      float rInnerMitered = (f.rInner - f.miterPush) - yOffset / tan(f.miterAngle);
      e.passedInnerGate = (q.x >= rInnerMitered);
      if (e.passedInnerGate) {
        e.signedDist = q.y - edgeY;
      } else {
        e.signedDist = q.y;
      }
      e.edgeDist = abs(q.y - edgeY);
      return e;
    }

    inline float computeMask(float2 p, IrisFrame f, constant IrisConfig& cfg) {
      float minSignedDist = 1e10f;
      for (int i = 0; i < f.N; i++) {
        BladeEval e = evalBlade(p, i, f);
        minSignedDist = min(minSignedDist, e.signedDist);
      }
      float apertureInset = cfg.seamWidth * 0.5f;
      return smoothstepEdge(-cfg.edgeSoftness, cfg.edgeSoftness, minSignedDist - apertureInset);
    }

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

    kernel void irisGlassMaskKernel(
      texture2d<float, access::write> outTex [[texture(0)]],
      constant IrisConfig& cfg [[buffer(0)]],
      constant IrisParams& params [[buffer(1)]],
      uint2 gid [[thread_position_in_grid]]
    ) {
      int width = params.width;
      int height = params.height;
      if (int(gid.x) >= width || int(gid.y) >= height) return;

      float u = (float(gid.x) + 0.5f) / float(width);
      float v = (float(gid.y) + 0.5f) / float(height);
      float py = params.flipY ? ((1.0f - v) * 2.0f - 1.0f) : (v * 2.0f - 1.0f);
      float px = u * 2.0f - 1.0f;

      float2 p = float2(px, py);
      float r = min(1.0f, length(p));

      IrisFrame frame = makeFrame(params.t, cfg);
      float m = computeMask(p, frame, cfg);
      float seam = computeSeamMask(p, frame, cfg);

      float glassA = cfg.glassAlpha * (1.0f - m);
      float seamIntensity = seam * (1.0f - m);

      float blendedR = cfg.glassColorR * (1.0f - seamIntensity) + cfg.seamColorR * seamIntensity;
      float blendedG = cfg.glassColorG * (1.0f - seamIntensity) + cfg.seamColorG * seamIntensity;
      float blendedB = cfg.glassColorB * (1.0f - seamIntensity) + cfg.seamColorB * seamIntensity;
      float blendedA = glassA * (1.0f - seamIntensity) + cfg.seamAlpha * seamIntensity;

      float finalAlpha = (r > 1.0f) ? 0.0f : blendedA;

      float4 color = float4(
        blendedB * finalAlpha / 255.0f,
        blendedG * finalAlpha / 255.0f,
        blendedR * finalAlpha / 255.0f,
        finalAlpha
      );

      outTex.write(color, gid);
    }
    """
}
