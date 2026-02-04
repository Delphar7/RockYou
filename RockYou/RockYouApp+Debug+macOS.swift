//
//  RockYouApp+Debug+macOS.swift
//  RockYou
//
//  Debug-only macOS support: render harness views, DPad refraction generator,
//  and the Metal compute kernel for barrel-distortion + chromatic dispersion.
//
//  This file is excluded from Release builds in the Xcode project.
//

import AppKit
import Metal
import SwiftUI

// MARK: - Debug Menu Support

/// Button to open a debug render window.
struct OpenDebugRenderWindowButton: View {
  let title: String
  let windowId: String
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button(title) {
      openWindow(id: windowId)
    }
  }
}

// MARK: - Debug Render Harness

struct RealityDebugViewConfig {
  let title: String
  let durationSeconds: Double
  let distanceRange: ClosedRange<Double>
  let defaultYawDegrees: Double
  let defaultPitchDegrees: Double
  let defaultDistance: Double

  static let dome = RealityDebugViewConfig(
    title: "Dome Debug",
    durationSeconds: 8.0,
    distanceRange: 0.6...1.6,
    defaultYawDegrees: 0,
    defaultPitchDegrees: 70,
    defaultDistance: 0.95
  )

  static let breaker = RealityDebugViewConfig(
    title: "Breaker Debug",
    durationSeconds: 1.0,
    distanceRange: 0.6...1.6,
    defaultYawDegrees: 0,
    defaultPitchDegrees: 0,
    defaultDistance: Double(BreakerSceneConfig.cameraDistance)
  )
}

struct DomeRenderDebugView: View {
  private let config = RealityDebugViewConfig.dome
  @State private var timeSeconds: Double
  @State private var yawDegrees: Double
  @State private var pitchDegrees: Double
  @State private var cameraDistance: Double
  @State private var useFreeCamera: Bool = true

  init() {
    let config = RealityDebugViewConfig.dome
    _timeSeconds = State(initialValue: 0)
    _yawDegrees = State(initialValue: config.defaultYawDegrees)
    _pitchDegrees = State(initialValue: config.defaultPitchDegrees)
    _cameraDistance = State(initialValue: config.defaultDistance)
  }

  var body: some View {
    let progress = CGFloat(timeSeconds / config.durationSeconds)
    let renderSize = CGFloat(DomeSceneConfig.dpadRenderSize * DomeSceneConfig.renderCanvasScale)

    HStack(spacing: 20) {
      DomeDoorsView(
        openProgress: progress,
        debugCameraOrbit: useFreeCamera
          ? DomeDebugCameraOrbit(
            yawDegrees: Float(yawDegrees),
            pitchDegrees: Float(pitchDegrees),
            distance: Float(cameraDistance)
          )
          : nil
      )
      .frame(width: renderSize, height: renderSize)

      DebugRenderControlPanel(
        config: config,
        timeSeconds: $timeSeconds,
        yawDegrees: $yawDegrees,
        pitchDegrees: $pitchDegrees,
        distance: $cameraDistance,
        onReset: {
          yawDegrees = config.defaultYawDegrees
          pitchDegrees = config.defaultPitchDegrees
          cameraDistance = config.defaultDistance
          timeSeconds = 0
        },
        cameraControlsDisabled: !useFreeCamera,
        extras: {
          Toggle("Free Camera", isOn: $useFreeCamera)
        }
      )
      .frame(width: 220)
    }
    .padding(20)
  }
}

struct BreakerRenderDebugView: View {
  private let config = RealityDebugViewConfig.breaker
  @State private var timeSeconds: Double
  @State private var yawDegrees: Double
  @State private var pitchDegrees: Double
  @State private var cameraDistance: Double

  init() {
    let config = RealityDebugViewConfig.breaker
    _timeSeconds = State(initialValue: 0)
    _yawDegrees = State(initialValue: config.defaultYawDegrees)
    _pitchDegrees = State(initialValue: config.defaultPitchDegrees)
    _cameraDistance = State(initialValue: config.defaultDistance)
  }

  var body: some View {
    let progressValue = CGFloat(timeSeconds / config.durationSeconds)
    let debugOrbit = BreakerDebugCameraOrbit(
      yawDegrees: Float(yawDegrees),
      pitchDegrees: Float(pitchDegrees),
      distance: Float(cameraDistance)
    )

    HStack(spacing: 20) {
      BreakerSwitchView(
        progress: progressValue,
        debugCameraOrbit: debugOrbit
      )
      .frame(width: 520, height: 520)
      .background(Color.black.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

      DebugRenderControlPanel(
        config: config,
        timeSeconds: $timeSeconds,
        yawDegrees: $yawDegrees,
        pitchDegrees: $pitchDegrees,
        distance: $cameraDistance,
        onReset: {
          yawDegrees = config.defaultYawDegrees
          pitchDegrees = config.defaultPitchDegrees
          cameraDistance = config.defaultDistance
          timeSeconds = 0
        }
      )
      .frame(width: 220)
    }
    .padding(20)
  }
}

struct DebugRenderControlPanel<Extras: View>: View {
  let config: RealityDebugViewConfig
  @Binding var timeSeconds: Double
  @Binding var yawDegrees: Double
  @Binding var pitchDegrees: Double
  @Binding var distance: Double
  let onReset: () -> Void
  let cameraControlsDisabled: Bool
  let displayYawText: String?
  let displayPitchText: String?
  let displayPositionText: String?
  let displayDistanceText: String?
  /// Optional scene-specific controls (keep empty unless truly needed).
  @ViewBuilder var extras: () -> Extras

  private var cameraPosition: (x: Double, y: Double, z: Double) {
    let yawRadians = yawDegrees * .pi / 180
    let pitchRadians = pitchDegrees * .pi / 180
    let r = max(0.1, distance)
    let x = sin(yawRadians) * cos(pitchRadians) * r
    let z = cos(yawRadians) * cos(pitchRadians) * r
    let y = sin(pitchRadians) * r
    return (x, y, z)
  }

  private var cameraPositionText: String {
    String(format: "%.2f, %.2f, %.2f", cameraPosition.x, cameraPosition.y, cameraPosition.z)
  }

  private var cameraOrientationText: String {
    String(format: "yaw %.0f°, pitch %.0f°", yawDegrees, pitchDegrees)
  }

  init(
    config: RealityDebugViewConfig,
    timeSeconds: Binding<Double>,
    yawDegrees: Binding<Double>,
    pitchDegrees: Binding<Double>,
    distance: Binding<Double>,
    onReset: @escaping () -> Void,
    cameraControlsDisabled: Bool = false,
    displayYawText: String? = nil,
    displayPitchText: String? = nil,
    displayPositionText: String? = nil,
    displayDistanceText: String? = nil,
    @ViewBuilder extras: @escaping () -> Extras = { EmptyView() }
  ) {
    self.config = config
    _timeSeconds = timeSeconds
    _yawDegrees = yawDegrees
    _pitchDegrees = pitchDegrees
    _distance = distance
    self.onReset = onReset
    self.cameraControlsDisabled = cameraControlsDisabled
    self.displayYawText = displayYawText
    self.displayPitchText = displayPitchText
    self.displayPositionText = displayPositionText
    self.displayDistanceText = displayDistanceText
    self.extras = extras
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(config.title)
        .font(.headline)

      DebugCameraControlBlock(
        yawDegrees: $yawDegrees,
        pitchDegrees: $pitchDegrees,
        distance: $distance,
        distanceRange: config.distanceRange,
        isDisabled: cameraControlsDisabled,
        displayYawText: displayYawText,
        displayPitchText: displayPitchText,
        displayDistanceText: displayDistanceText
      )

      DebugCameraInfoBlock(
        positionText: displayPositionText ?? cameraPositionText
      )

      DebugTimeControlBlock(
        timeSeconds: $timeSeconds,
        durationSeconds: config.durationSeconds
      )

      extras()

      Button("Reset View") {
        onReset()
      }

      Spacer()
    }
  }
}

private struct DebugCameraControlBlock: View {
  @Binding var yawDegrees: Double
  @Binding var pitchDegrees: Double
  @Binding var distance: Double
  let distanceRange: ClosedRange<Double>
  let isDisabled: Bool
  let displayYawText: String?
  let displayPitchText: String?
  let displayDistanceText: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DomeOrbitControl(yawDegrees: $yawDegrees, pitchDegrees: $pitchDegrees)
        .frame(width: 180, height: 180)

      LabeledContent("Yaw") {
        Text(displayYawText ?? String(format: "%.0f°", yawDegrees))
          .frame(width: 64, alignment: .trailing)
      }

      LabeledContent("Pitch") {
        Text(displayPitchText ?? String(format: "%.0f°", pitchDegrees))
          .frame(width: 64, alignment: .trailing)
      }

      LabeledContent("Distance") {
        Text(displayDistanceText ?? String(format: "%.2f", distance))
          .frame(width: 64, alignment: .trailing)
      }

      Slider(value: $distance, in: distanceRange)
    }
    .opacity(isDisabled ? 0.4 : 1.0)
    .disabled(isDisabled)
  }
}

private struct DebugCameraInfoBlock: View {
  let positionText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()

      Text("Camera (look at 0,0,0)")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      LabeledContent("Position") {
        Text(positionText)
      }

    }
  }
}

private struct DebugTimeControlBlock: View {
  @Binding var timeSeconds: Double
  let durationSeconds: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider()

      LabeledContent("Time") {
        Text("\(timeSeconds, specifier: "%.2f")s")
          .frame(width: 64, alignment: .trailing)
      }
      Slider(value: $timeSeconds, in: 0...durationSeconds)
    }
  }
}

private struct DomeOrbitControl: View {
  @Binding var yawDegrees: Double
  @Binding var pitchDegrees: Double
  @State private var startYaw: Double = 0
  @State private var startPitch: Double = 0

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let center = CGPoint(x: size / 2, y: size / 2)
      ZStack {
        Circle()
          .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
        Path { path in
          path.move(to: CGPoint(x: center.x, y: 0))
          path.addLine(to: CGPoint(x: center.x, y: size))
          path.move(to: CGPoint(x: 0, y: center.y))
          path.addLine(to: CGPoint(x: size, y: center.y))
        }
        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)

        Text("X")
          .font(.caption)
          .foregroundStyle(Color.red)
          .position(x: size - 12, y: center.y)
        Text("Y")
          .font(.caption)
          .foregroundStyle(Color.green)
          .position(x: center.x, y: 12)
        Text("Z")
          .font(.caption)
          .foregroundStyle(Color.blue)
          .position(x: center.x + 26, y: center.y + 26)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if value.startLocation == value.location {
              startYaw = yawDegrees
              startPitch = pitchDegrees
            }
            let dx = Double(value.translation.width)
            let dy = Double(value.translation.height)
            yawDegrees = startYaw + dx * 0.6
            pitchDegrees = min(89, max(0, startPitch - dy * 0.6))
          }
      )
    }
  }
}

// MARK: - Refracted DPad Generator

@MainActor
enum DebugRefractedDPadGenerator {
  static func generateAndRevealInFinder() async {
    do {
      // NSOpenPanel grants implicit Powerbox write access for the selected directory.
      // No startAccessingSecurityScopedResource needed (that's for bookmark-resolved URLs).
      let outDir = try await pickOutputDirectory()
      let (regularURL, refractedURL) = try await generateAndSavePNGs(to: outDir)
      Log.info("Debug", "Saved DPad PNGs: \(regularURL.path), \(refractedURL.path)")
      NSWorkspace.shared.activateFileViewerSelecting([regularURL, refractedURL])
    } catch {
      Log.error("Debug", "Generate refracted DPad failed: \(error)")
    }
  }

  private static func generateAndSavePNGs(to outDir: URL) async throws
    -> (regular: URL, refracted: URL)
  {
    // Render at the DPad asset-native resolution for baking.
    let baseDPadPixels: CGFloat = 1024
    let overscanMultiplier: CGFloat = 1.25
    let outputPixels = (baseDPadPixels * overscanMultiplier).rounded(.toNearestOrAwayFromZero)
    // Use scale=1 so "points == pixels" for the baked output.
    let scale: CGFloat = 1.0

    // 1) Render a snapshot of the DPad at the current UI scale.
    let sourceImage = try renderDPadCGImage(
      baseDPadSize: baseDPadPixels,
      outputSize: outputPixels,
      scale: scale
    )

    // For iteration: keep the bake pipeline high-res, but write a smaller PNG.
    // PNG is lossless; halving the dimensions gives a large size win without visible loss here.
    let finalPixels: Int = 640

    // 1b) Save the base (un-refracted) image.
    let regularURL = outDir.appendingPathComponent("DPad-Regular.png")
    let baseRep = NSBitmapImageRep(cgImage: downsampleCGImage(sourceImage, to: finalPixels))
    guard let basePNG = baseRep.representation(using: .png, properties: [:]) else {
      throw NSError(
        domain: "RockYou.DebugRefractedDPad", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode base PNG"])
    }
    try basePNG.write(to: regularURL)
    Log.info("Debug", "Saved base DPad: \(regularURL.path)")

    // 2) Apply a refraction-like warp using a debug-only Metal compute kernel.
    let refractedFullRes = try MetalDPadRefractor.refract(
      cgImage: sourceImage,
      strength: 0.17,
      dispersion: 0.004
    )

    // 3) Save the refracted image.
    let refractedURL = outDir.appendingPathComponent("DPad-Refracted.png")
    let refracted = downsampleCGImage(refractedFullRes, to: finalPixels)
    let rep = NSBitmapImageRep(cgImage: refracted)
    guard let refractedPNG = rep.representation(using: .png, properties: [:]) else {
      throw NSError(
        domain: "RockYou.DebugRefractedDPad", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode refracted PNG"])
    }
    try refractedPNG.write(to: refractedURL)

    return (regularURL, refractedURL)
  }

  /// Present an `NSOpenPanel` pre-navigated to `Resources/Shipping/` so the user can
  /// grant write access with a single click. Returns a security-scoped directory URL.
  private static func pickOutputDirectory() async throws -> URL {
    let thisFile = URL(fileURLWithPath: #filePath)
    let projectRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent()
    let defaultDir = projectRoot.appendingPathComponent("Resources/Shipping", isDirectory: true)

    return try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.main.async {
        let panel = NSOpenPanel()
        panel.title = "Select output directory for DPad PNGs"
        panel.message = "Grant write access to Resources/Shipping"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultDir

        let response = panel.runModal()
        if response == .OK, let url = panel.url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(
            throwing: NSError(
              domain: "RockYou.DebugRefractedDPad", code: 2,
              userInfo: [NSLocalizedDescriptionKey: "User cancelled directory selection"]))
        }
      }
    }
  }

  private static func downsampleCGImage(_ image: CGImage, to targetSize: Int) -> CGImage {
    let width = max(1, targetSize)
    let height = max(1, targetSize)

    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo.byteOrder32Little.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
    let bytesPerRow = width * 4
    var data = [UInt8](repeating: 0, count: bytesPerRow * height)

    guard
      let ctx = CGContext(
        data: &data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: cs,
        bitmapInfo: info.rawValue
      )
    else { return image }

    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let out = ctx.makeImage() else { return image }
    return out
  }

  private static func renderDPadCGImage(
    baseDPadSize: CGFloat,
    outputSize: CGFloat,
    scale: CGFloat
  ) throws -> CGImage {
    // Overscan canvas with the DPad centered; transparent padding prevents rim effects
    // from hard-clipping at the image edge.
    let view =
      ZStack {
        Color.clear
          .frame(width: outputSize, height: outputSize)

        DPadView.renderOnly(size: baseDPadSize)
          .frame(width: baseDPadSize, height: baseDPadSize)
      }
      .frame(width: outputSize, height: outputSize)

    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.proposedSize = ProposedViewSize(width: outputSize, height: outputSize)

    guard let image = renderer.cgImage else {
      throw NSError(
        domain: "RockYou.DebugRefractedDPad", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to snapshot DPadView via ImageRenderer"
        ])
    }
    return image
  }
}

// MARK: - Metal Barrel Distortion + Chromatic Dispersion

private enum MetalDPadRefractor {
  struct Params {
    var strength: Float
    var dispersion: Float
    var _pad0: Float = 0
    var _pad1: Float = 0
  }

  static func refract(cgImage: CGImage, strength: Float, dispersion: Float) throws -> CGImage {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "No Metal device available"
        ])
    }

    let source = metalSource
    let library = try device.makeLibrary(source: source, options: nil)
    guard let fn = library.makeFunction(name: "refractKernel") else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "Missing Metal function refractKernel"
        ])
    }
    let pipeline = try device.makeComputePipelineState(function: fn)
    guard let queue = device.makeCommandQueue() else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create Metal command queue"
        ])
    }

    let inTex = try makeBGRA8Texture(device: device, cgImage: cgImage)

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: inTex.width,
      height: inTex.height,
      mipmapped: false
    )
    desc.usage = [.shaderWrite, .shaderRead]
    desc.storageMode = .shared
    guard let outTex = device.makeTexture(descriptor: desc) else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 4,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create output texture"
        ])
    }

    var p = Params(strength: strength, dispersion: dispersion)
    let pData = Data(bytes: &p, count: MemoryLayout<Params>.stride)

    guard let commandBuffer = queue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 5,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create Metal command buffer/encoder"
        ])
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setTexture(inTex, index: 0)
    encoder.setTexture(outTex, index: 1)
    encoder.setBytes((pData as NSData).bytes, length: pData.count, index: 0)

    let w = pipeline.threadExecutionWidth
    let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
    let tg = MTLSize(width: w, height: h, depth: 1)
    let grid = MTLSize(width: outTex.width, height: outTex.height, depth: 1)
    encoder.dispatchThreads(grid, threadsPerThreadgroup: tg)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    return try cgImageFromBGRA8Texture(outTex)
  }

  private static func makeBGRA8Texture(device: MTLDevice, cgImage: CGImage) throws -> MTLTexture {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel

    // Force the CGImage into BGRA8 (premultipliedFirst, little endian) so Metal can consume it.
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo.byteOrder32Little.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
    guard
      let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: cs,
        bitmapInfo: info.rawValue
      )
    else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 10,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create BGRA CGContext for texture upload"
        ])
    }

    // Draw into the buffer. (CGImage has no orientation; this is a direct pixel copy.)
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    desc.usage = [.shaderRead]
    desc.storageMode = .shared
    guard let tex = device.makeTexture(descriptor: desc) else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 11,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create input texture"
        ])
    }

    tex.replace(
      region: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0,
      withBytes: pixels,
      bytesPerRow: bytesPerRow
    )
    return tex
  }

  private static func cgImageFromBGRA8Texture(_ tex: MTLTexture) throws -> CGImage {
    let width = tex.width
    let height = tex.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var data = [UInt8](repeating: 0, count: bytesPerRow * height)
    tex.getBytes(
      &data, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGBitmapInfo.byteOrder32Little.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
    guard
      let provider = CGDataProvider(data: Data(data) as CFData),
      let img = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: cs,
        bitmapInfo: info,
        provider: provider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    else {
      throw NSError(
        domain: "RockYou.MetalDPadRefractor", code: 6,
        userInfo: [
          NSLocalizedDescriptionKey: "Failed to create CGImage from output texture"
        ])
    }
    return img
  }

  // Inline Metal source to avoid Xcode project file changes for a debug-only tool.
  private static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params {
      float strength;
      float dispersion;
      float _pad0;
      float _pad1;
    };

    kernel void refractKernel(
      texture2d<float, access::sample> inTex [[texture(0)]],
      texture2d<float, access::write> outTex [[texture(1)]],
      constant Params& p [[buffer(0)]],
      uint2 gid [[thread_position_in_grid]]
    ) {
      if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) { return; }

      constexpr sampler s(address::clamp_to_edge, filter::linear);

      float2 size = float2(outTex.get_width(), outTex.get_height());
      float2 uv = (float2(gid) + 0.5) / size;

      float2 c = uv - 0.5;
      float r = length(c) * 2.0;  // ~0..~1.41
      float2 dir = normalize(c + 1e-6);

      // Center-bulge / lens distortion (barrel-ish). This matches the *center* of a dome:
      // the middle looks slightly magnified with a gentle falloff toward the edge.
      float r2 = r * r;
      float denom = 1.0 + p.strength * r2;
      float2 uvBase = 0.5 + (c / denom);

      // Chromatic dispersion: tiny radial offset from the base sample point.
      float disp = p.dispersion * r2;
      float2 uvR = uvBase + dir * disp;
      float2 uvG = uvBase;
      float2 uvB = uvBase - dir * disp;

      float4 cr = inTex.sample(s, uvR);
      float4 cg = inTex.sample(s, uvG);
      float4 cb = inTex.sample(s, uvB);

      float3 rgb = float3(cr.r, cg.g, cb.b);
      float a = cg.a;

      // Very subtle rim brighten (glass edge catching light).
      float rim = smoothstep(0.70, 1.15, r);
      rgb += rim * 0.02;

      // Tiny blur along the radial direction to hint at rough refraction (keep subtle).
      float2 blur = dir * disp * 0.75;
      float4 b0 = inTex.sample(s, uvG - blur);
      float4 b1 = inTex.sample(s, uvG + blur);
      rgb = mix(rgb, (b0.rgb + b1.rgb) * 0.5, 0.06);

      outTex.write(float4(rgb, a), gid);
    }
    """
}
