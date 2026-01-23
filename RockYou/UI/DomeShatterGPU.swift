// DomeShatterGPU.swift
// RockYou
//
// GPU-driven fragment shatter system. All physics computed on GPU.
// Single draw call for all fragments.

import Combine
import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

#if os(macOS)
  import AppKit

  private let gpuLog = Logger(subsystem: "com.rockyou", category: "GPUShatter")

  /// GPU-based shatter simulation - all physics on GPU, single mesh/draw call
  @MainActor
  class DomeShatterGPU: ObservableObject {
    @Published var isActive: Bool = false
    @Published private(set) var fragmentCount: Int = 0

    /// Published visibility result - updates when compute shader detects all fragments gone
    @Published var allFragmentsGone: Bool = false

    /// Use GPU compute shader for mesh generation
    @Published var useComputeGenerator: Bool = true

    private var entity: ModelEntity?
    private var currentCameraPosition: SIMD3<Float> = .zero
    private var currentTime: Float = 0

    // Physics data texture (stores initial conditions for each fragment)
    private var dataTexture: TextureResource?
    private var mtlDataTexture: MTLTexture?  // Raw Metal texture for compute shader

    // Visibility checking
    private var visibilityChecker: VisibilityChecker?
    private var lastVisibilityCheckTime: Float = -1

    // GPU compute mesh generator (lazy initialized)
    private lazy var computeGenerator: DomeComputeGenerator? = DomeComputeGenerator()

    /// Start GPU-driven shatter - NEW: shader computes everything from header!
    func start(
      fragmentCount targetCount: Int,
      radius: Float,
      in anchor: Entity,
      config: DomeShatterConfig,
      waveOrigin: SIMD3<Float>?,
      waveSpeed: Float,
      cameraPosition: SIMD3<Float>,
      doubleSided: Bool = true
    ) {
      guard !isActive else { return }

      isActive = true

      // Compute tessellation segments (same formula as generateTessellatedDome)
      let segments = max(4, Int(sqrt(Double(targetCount))))
      let latSegments = segments / 2
      let lonSegments = segments

      // Actual triangle count from tessellation
      let actualCount = lonSegments + (latSegments - 1) * lonSegments * 2
      fragmentCount = actualCount

      // Create mesh - choose between CPU and GPU compute paths
      let mesh: MeshResource?
      if useComputeGenerator, let generator = computeGenerator {
        mesh = generator.generateMesh(
          latSegments: latSegments,
          lonSegments: lonSegments,
          radius: radius
        )
      } else {
        mesh = createTessellatedMesh(
          radius: radius,
          latSegments: latSegments,
          lonSegments: lonSegments
        )
      }
      guard let mesh else {
        gpuLog.error("Failed to create mesh")
        isActive = false
        return
      }

      // Create header-only texture (lookup tables + dome/wave params)
      guard let dataTex = createDataTexture(
        config: config,
        radius: radius,
        latSegments: latSegments,
        lonSegments: lonSegments,
        waveOrigin: waveOrigin,
        waveSpeed: waveSpeed
      ) else {
        gpuLog.error("Failed to create texture")
        isActive = false
        return
      }
      dataTexture = dataTex

      // Create material
      guard let material = createGPUMaterial(
        dataTexture: dataTex,
        cameraPosition: cameraPosition,
        doubleSided: doubleSided
      ) else {
        gpuLog.error("Failed to create material")
        isActive = false
        return
      }

      // Create entity
      let fragmentEntity = ModelEntity(mesh: mesh, materials: [material])
      anchor.addChild(fragmentEntity)
      entity = fragmentEntity

      // Initialize at time 0
      currentTime = 0
      currentCameraPosition = cameraPosition
      updateMaterial()
    }

    /// Creates mesh for tessellated dome - vertices only, shader computes centers
    private func createTessellatedMesh(
      radius: Float,
      latSegments: Int,
      lonSegments: Int
    ) -> MeshResource? {
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var uvs: [SIMD2<Float>] = []
      var indices: [UInt32] = []

      // Precompute trig tables
      var sinTheta: [Float] = []
      var cosTheta: [Float] = []
      for lat in 0...latSegments {
        let theta = (Float(lat) / Float(latSegments)) * (Float.pi / 2)
        sinTheta.append(sin(theta))
        cosTheta.append(cos(theta))
      }

      var sinPhi: [Float] = []
      var cosPhi: [Float] = []
      for lon in 0...lonSegments {
        let phi = (Float(lon) / Float(lonSegments)) * 2 * Float.pi
        sinPhi.append(sin(phi))
        cosPhi.append(cos(phi))
      }

      var fragmentIndex = 0

      // Generate triangles matching shader's computation
      for lat in 0..<latSegments {
        let st1 = sinTheta[lat]
        let ct1 = cosTheta[lat]
        let st2 = sinTheta[lat + 1]
        let ct2 = cosTheta[lat + 1]

        for lon in 0..<lonSegments {
          let sp1 = sinPhi[lon]
          let cp1 = cosPhi[lon]
          let sp2 = sinPhi[lon + 1]
          let cp2 = cosPhi[lon + 1]

          // Four corners
          let p00 = SIMD3<Float>(radius * st1 * cp1, radius * ct1, radius * st1 * sp1)
          let p10 = SIMD3<Float>(radius * st2 * cp1, radius * ct2, radius * st2 * sp1)
          let p01 = SIMD3<Float>(radius * st1 * cp2, radius * ct1, radius * st1 * sp2)
          let p11 = SIMD3<Float>(radius * st2 * cp2, radius * ct2, radius * st2 * sp2)

          if lat == 0 {
            // Pole triangle: [p00, p11, p10]
            let fn = computeFaceNormal(p00, p11, p10)
            let baseIdx = UInt32(positions.count)
            positions.append(contentsOf: [p00, p11, p10])
            normals.append(contentsOf: [fn, fn, fn])
            // UV.x = fragmentIndex (shader reads this to compute center)
            uvs.append(contentsOf: [
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
            ])
            indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
            fragmentIndex += 1
          } else {
            // Quad: two triangles
            // Triangle 0: [p00, p11, p10]
            let fn1 = computeFaceNormal(p00, p11, p10)
            var baseIdx = UInt32(positions.count)
            positions.append(contentsOf: [p00, p11, p10])
            normals.append(contentsOf: [fn1, fn1, fn1])
            uvs.append(contentsOf: [
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
            ])
            indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
            fragmentIndex += 1

            // Triangle 1: [p00, p01, p11]
            let fn2 = computeFaceNormal(p00, p01, p11)
            baseIdx = UInt32(positions.count)
            positions.append(contentsOf: [p00, p01, p11])
            normals.append(contentsOf: [fn2, fn2, fn2])
            uvs.append(contentsOf: [
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
              SIMD2<Float>(Float(fragmentIndex), 0),
            ])
            indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
            fragmentIndex += 1
          }
        }
      }

      var desc = MeshDescriptor(name: "gpu_dome_fragments")
      desc.positions = MeshBuffers.Positions(positions)
      desc.normals = MeshBuffers.Normals(normals)
      desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
      desc.primitives = .triangles(indices)

      do {
        return try MeshResource.generate(from: [desc])
      } catch {
        gpuLog.error("Mesh generation failed: \(error)")
        return nil
      }
    }

    private func computeFaceNormal(_ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>) -> SIMD3<Float> {
      let edge1 = v1 - v0
      let edge2 = v2 - v0
      var normal = simd_normalize(simd_cross(edge1, edge2))
      let center = (v0 + v1 + v2) / 3.0
      if simd_dot(normal, center) < 0 {
        normal = -normal
      }
      return normal
    }

    func stop() {
      entity?.removeFromParent()
      entity = nil
      dataTexture = nil
      mtlDataTexture = nil
      isActive = false
      fragmentCount = 0
      currentTime = 0
      allFragmentsGone = false
      lastVisibilityCheckTime = -1
    }

    /// Set the simulation time (called by view when time changes)
    func setTime(_ time: Float) {
      currentTime = time
      updateMaterial()

      // Check visibility periodically (not every frame)
      let checkInterval: Float = 0.5  // Check twice per second
      if time - lastVisibilityCheckTime >= checkInterval {
        lastVisibilityCheckTime = time
        checkVisibility(at: time)
      }
    }

    /// Check if any fragments are still visible using GPU compute shader
    private func checkVisibility(at time: Float) {
      guard isActive, !allFragmentsGone else { return }
      guard let mtlTexture = mtlDataTexture else { return }

      // Lazily create visibility checker
      if visibilityChecker == nil {
        visibilityChecker = VisibilityChecker()
      }
      guard let checker = visibilityChecker else { return }

      // Use async check to avoid blocking main thread
      let count = fragmentCount
      checker.checkVisibilityAsync(
        animation: DomeShatterVisibilityAdapter(texture: mtlTexture, fragmentCount: count),
        time: time
      ) { [weak self] result in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if result == .allGone {
            self.allFragmentsGone = true
            Log.info("DomeShatterGPU", "All fragments gone at t=\(time)")
          }
        }
      }
    }

    /// Update camera position for front/back face detection
    func updateCamera(position: SIMD3<Float>) {
      currentCameraPosition = position
      updateMaterial()
    }

    private func updateMaterial() {
      guard let entity else { return }
      if var material = entity.model?.materials.first as? CustomMaterial {
        material.custom.value = [
          currentTime, currentCameraPosition.x, currentCameraPosition.y, currentCameraPosition.z,
        ]
        entity.model?.materials = [material]
      }
    }

    // MARK: - Texture Layout Constants
    // Texture is ONLY lookup tables + header - no per-fragment data!
    // Shader computes center position and spawnTime from fragmentIndex.
    // Header (row 0, cols 3-6): radius, segments, waveOrigin, waveSpeed
    private static let lookupTableSize = 4096
    private static let textureWidth = 16  // Only need columns for lookup + header

    /// Encode a float to 16-bit using given range
    private func encode16bit(_ value: Float, min: Float, max: Float) -> UInt16 {
      let range = max - min
      let normalized = (value - min) / range
      let clamped = Swift.max(0.0, Swift.min(1.0, normalized))
      return UInt16(clamped * 65535.0)
    }

    /// Encode a float to 8-bit using given range
    private func encode8bit(_ value: Float, min: Float, max: Float) -> UInt8 {
      let range = max - min
      let normalized = (value - min) / range
      let clamped = Swift.max(0, Swift.min(1, normalized))
      return UInt8((clamped * 255).rounded())
    }

    /// Create texture with lookup tables + header (NO per-fragment data!)
    /// Shader computes center and spawnTime from fragmentIndex + header params.
    private func createDataTexture(
      config: DomeShatterConfig,
      radius: Float,
      latSegments: Int,
      lonSegments: Int,
      waveOrigin: SIMD3<Float>?,
      waveSpeed: Float
    ) -> TextureResource? {
      // Layout (16 x 4096):
      // Rows 0-4095: Lookup tables (4096 random parameter sets)
      //   Col 0: velocity.xyz (±0.5), gravity (±2)
      //   Col 1: angularVelocity.xyz (±10), unused
      //   Col 2: rotation quaternion (±1)
      //   Col 3 (row 0): radius (RG 16-bit), latSegments (BA 16-bit)
      //   Col 4 (row 0): lonSegments (RG), waveSpeed (BA)
      //   Col 5 (row 0): waveOrigin.x (RG), waveOrigin.y (BA)
      //   Col 6 (row 0): waveOrigin.z (RG), waveEnabled (BA: 0 or 1)

      let width = Self.textureWidth
      let height = Self.lookupTableSize

      let effectiveWaveOrigin = waveOrigin ?? .zero
      let waveEnabled: UInt16 = waveOrigin != nil ? 1 : 0

      var pixels: [UInt8] = []
      pixels.reserveCapacity(width * height * 4)

      for rowIdx in 0..<height {
        // Col 0: velocity.xyz + gravity
        let randomDir = simd_normalize(SIMD3<Float>(
          Float.random(in: -1...1),
          Float.random(in: 0...1),
          Float.random(in: -1...1)
        ))
        let vel = SIMD3<Float>(
          randomDir.x * config.baseSpeed + Float.random(in: -config.spreadAngle...config.spreadAngle),
          randomDir.y * config.baseSpeed + config.upwardBias + Float.random(in: 0...config.spreadAngle),
          randomDir.z * config.baseSpeed + Float.random(in: -config.spreadAngle...config.spreadAngle)
        )
        let gravity = config.baseGravity * Float.random(in: config.gravityMin...config.gravityMax)
        pixels.append(encode8bit(vel.x, min: -0.5, max: 0.5))
        pixels.append(encode8bit(vel.y, min: -0.5, max: 0.5))
        pixels.append(encode8bit(vel.z, min: -0.5, max: 0.5))
        pixels.append(encode8bit(gravity, min: -2.0, max: 2.0))

        // Col 1: angularVelocity.xyz + unused
        let spinAxis = simd_normalize(SIMD3<Float>(
          Float.random(in: -1...1),
          Float.random(in: -1...1),
          Float.random(in: -1...1)
        ))
        let spinRate = Float.random(in: config.spinRateMin...config.spinRateMax)
        let angVel = spinAxis * spinRate
        pixels.append(encode8bit(angVel.x, min: -10.0, max: 10.0))
        pixels.append(encode8bit(angVel.y, min: -10.0, max: 10.0))
        pixels.append(encode8bit(angVel.z, min: -10.0, max: 10.0))
        pixels.append(128)

        // Col 2: rotation quaternion
        let randomAxis = simd_normalize(SIMD3<Float>(
          Float.random(in: -1...1),
          Float.random(in: -1...1),
          Float.random(in: -1...1)
        ))
        let randomAngle = Float.random(in: 0...(2 * .pi))
        let q = simd_quatf(angle: randomAngle, axis: randomAxis)
        pixels.append(encode8bit(q.vector.x, min: -1.0, max: 1.0))
        pixels.append(encode8bit(q.vector.y, min: -1.0, max: 1.0))
        pixels.append(encode8bit(q.vector.z, min: -1.0, max: 1.0))
        pixels.append(encode8bit(q.vector.w, min: -1.0, max: 1.0))

        // Cols 3-6: Header (row 0 only) or padding
        if rowIdx == 0 {
          // Col 3: radius (RG), latSegments (BA)
          let radius16 = encode16bit(radius, min: 0.0, max: 2.0)
          let latSegs16 = UInt16(clamping: latSegments)
          pixels.append(UInt8((radius16 >> 8) & 0xFF))
          pixels.append(UInt8(radius16 & 0xFF))
          pixels.append(UInt8((latSegs16 >> 8) & 0xFF))
          pixels.append(UInt8(latSegs16 & 0xFF))

          // Col 4: lonSegments (RG), waveSpeed (BA)
          let lonSegs16 = UInt16(clamping: lonSegments)
          let waveSpeed16 = encode16bit(waveSpeed, min: 0.0, max: 20.0)
          pixels.append(UInt8((lonSegs16 >> 8) & 0xFF))
          pixels.append(UInt8(lonSegs16 & 0xFF))
          pixels.append(UInt8((waveSpeed16 >> 8) & 0xFF))
          pixels.append(UInt8(waveSpeed16 & 0xFF))

          // Col 5: waveOrigin.x (RG), waveOrigin.y (BA)
          let wox16 = encode16bit(effectiveWaveOrigin.x, min: -2.0, max: 2.0)
          let woy16 = encode16bit(effectiveWaveOrigin.y, min: -2.0, max: 2.0)
          pixels.append(UInt8((wox16 >> 8) & 0xFF))
          pixels.append(UInt8(wox16 & 0xFF))
          pixels.append(UInt8((woy16 >> 8) & 0xFF))
          pixels.append(UInt8(woy16 & 0xFF))

          // Col 6: waveOrigin.z (RG), waveEnabled (BA)
          let woz16 = encode16bit(effectiveWaveOrigin.z, min: -2.0, max: 2.0)
          pixels.append(UInt8((woz16 >> 8) & 0xFF))
          pixels.append(UInt8(woz16 & 0xFF))
          pixels.append(UInt8((waveEnabled >> 8) & 0xFF))
          pixels.append(UInt8(waveEnabled & 0xFF))

          // Cols 7+: padding
          for _ in 7..<width {
            pixels.append(contentsOf: [128, 128, 128, 128])
          }
        } else {
          // Non-header rows: just padding for cols 3+
          for _ in 3..<width {
            pixels.append(contentsOf: [128, 128, 128, 128])
          }
        }
      }

      let bytesPerRow = width * 4
      let nsData = Data(pixels)
      guard let provider = CGDataProvider(data: nsData as CFData) else {
        gpuLog.error("CGDataProvider creation failed")
        return nil
      }

      // Use LINEAR color space to avoid gamma correction mangling our data!
      // CGColorSpaceCreateDeviceRGB() applies gamma which corrupts encoded integers.
      guard let linearColorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
        let cgImage = CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: bytesPerRow,
          space: linearColorSpace,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
      else {
        gpuLog.error("CGImage creation failed")
        return nil
      }

      // Create Metal texture for compute shader visibility checking
      if let device = MTLCreateSystemDefaultDevice() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .rgba8Unorm,
          width: width,
          height: height,
          mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        if let mtlTex = device.makeTexture(descriptor: descriptor) {
          let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                  size: MTLSize(width: width, height: height, depth: 1))
          pixels.withUnsafeBytes { ptr in
            mtlTex.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
          }
          self.mtlDataTexture = mtlTex
        }
      }

      do {
        return try TextureResource(image: cgImage, withName: "FragmentData", options: .init(semantic: .raw))
      } catch {
        gpuLog.error("TextureResource creation failed: \(error)")
        return nil
      }
    }

    /// Create material with geometry modifier and surface shader
    private func createGPUMaterial(
      dataTexture: TextureResource,
      cameraPosition: SIMD3<Float>,
      doubleSided: Bool
    ) -> RealityKit.Material? {
      guard let device = MTLCreateSystemDefaultDevice() else {
        gpuLog.error("No Metal device")
        return nil
      }
      guard let library = device.makeDefaultLibrary() else {
        gpuLog.error("No default Metal library")
        return nil
      }

      // Load DPad texture for env mapping
      var dpadTexture: TextureResource?
      if let path = Bundle.main.path(forResource: "DPad-Refracted", ofType: "png"),
        let native = PlatformImage.cachedNativeContentsOfFile(path),
        let cg = PlatformImage.cgImage(from: native)
      {
        dpadTexture = try? TextureResource(image: cg, withName: "DPad-GPU-Env", options: .init(semantic: .color))
      }

      do {
        // Geometry modifier for physics
        let geometryModifier = CustomMaterial.GeometryModifier(
          named: "fragmentGeometryModifier",
          in: library
        )

        // Surface shader - simple glass (dual-sided shader has issues)
        let surfaceShader = CustomMaterial.SurfaceShader(
          named: "fragmentGPUSurfaceShader",
          in: library
        )

        var material = try CustomMaterial(
          surfaceShader: surfaceShader,
          geometryModifier: geometryModifier,
          lightingModel: .lit
        )

        // Culling based on toggle: .none = double-sided, .back = front faces only
        material.faceCulling = doubleSided ? .none : .back
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))  // Let shader control opacity

        // custom_parameter: (time, cameraX, cameraY, cameraZ)
        // - time: used by geometry modifier for physics animation
        // - camera position: for back-face detection (dynamic, changes as user moves)
        // Static values (segments, radius) are in texture header with LINEAR color space
        material.custom.value = [0, cameraPosition.x, cameraPosition.y, cameraPosition.z]

        // Physics data texture
        material.custom.texture = .init(dataTexture)

        // DPad texture for env mapping
        if let tex = dpadTexture {
          material.baseColor.texture = .init(tex)
        }

        return material
      } catch {
        gpuLog.error("GPU material creation failed: \(error)")
        return nil
      }
    }
  }

  // MARK: - Visibility Adapter

  /// Adapter to make DomeShatterGPU work with VisibilityChecker
  /// Uses the texture-based compute kernel that reads from the same data texture as the geometry modifier
  private struct DomeShatterVisibilityAdapter: VisibilityCheckable {
    let texture: MTLTexture
    let fragmentCount: Int

    var visibilityKernelName: String { "domeShatter_visibility_texture" }

    func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder) {
      // Buffer 2: fragment count (buffer 0 = anyVisible, buffer 1 = time)
      var count = UInt32(fragmentCount)
      encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

      // Texture 0: data texture
      encoder.setTexture(texture, index: 0)
    }
  }

#endif
