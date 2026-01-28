// ShatterGPU.swift
// RockYou/UI/Debug/Playground
//
// GPU-driven fragment shatter system for playground experimentation.
// Supports multiple algorithms: explode, confetti, ripple, iris.
// Production code uses SceneView + IrisContent instead.

import Combine
import CoreGraphics
import Foundation
import Metal
import os
import RealityKit
import simd

private let gpuLog = Logger(subsystem: "com.rockyou", category: "GPUShatter")

  /// Algorithm for dome collapse animation
  enum DomeCollapseAlgorithm: Int, CaseIterable {
    case explode = 0   // Fragments fly outward with gravity
    case confetti = 1  // Fragments flutter down like confetti
    case ripple = 2    // Wave motion, random detach, collapse wave
    case iris = 3      // Iris mechanism blades fly off

    /// Metal geometry modifier function name for this algorithm
    var geometryModifierName: String {
      switch self {
      case .explode: return "explodeGeometryModifier"
      case .confetti: return "confettiGeometryModifier"
      case .ripple: return "rippleGeometryModifier"
      case .iris: return "irisGeometryModifier"
      }
    }

    /// Metal surface shader function name for this algorithm
    var surfaceShaderName: String {
      switch self {
      case .explode: return "fragmentSurfaceShader"
      case .confetti: return "confettiSurfaceShader"
      case .ripple: return "rippleSurfaceShader"
      case .iris: return "irisSurfaceShader"
      }
    }

    /// Metal visibility kernel function name for this algorithm
    var visibilityKernelName: String {
      switch self {
      case .explode: return "explodeVisibilityKernel"
      case .confetti: return "confettiVisibilityKernel"
      case .ripple: return "rippleVisibilityKernel"
      case .iris: return "irisVisibilityKernel"
      }
    }
  }

  /// GPU-based shatter simulation - all physics on GPU, single mesh/draw call
  @MainActor
  class DomeShatterGPU: ObservableObject {
    @Published var isActive: Bool = false
    @Published private(set) var fragmentCount: Int = 0

    /// Published visibility result - updates when compute shader detects all fragments gone
    @Published var allFragmentsGone: Bool = false

    private var entity: ModelEntity?
    private var seamRibbonEntity: ModelEntity?  // Ribbon mesh for iris seams
    private var currentCameraPosition: SIMD3<Float> = .zero
    private var currentTime: Float = 0
    private var currentAlgorithm: DomeCollapseAlgorithm = .explode

    // Physics data texture (stores initial conditions for each fragment)
    private var dataTexture: TextureResource?
    private var mtlDataTexture: MTLTexture?  // Raw Metal texture for compute shader

    // Visibility checking
    private var visibilityChecker: VisibilityChecker?
    private var lastVisibilityCheckTime: Float = -1

    // GPU compute mesh generator (lazy initialized)
    private lazy var meshGenerator: DomeMeshGenerator? = DomeMeshGenerator()

    /// Toggle seam ribbon visibility (for performance testing)
    func setSeamRibbonVisible(_ visible: Bool) {
      seamRibbonEntity?.isEnabled = visible
    }

    // MARK: - Clean Animation API

    /// Start a dome animation with typed configuration.
    /// This is the preferred API - configs are pure data structs defined in DomeAnimationConfigs.swift.
    func start(
      _ animation: DomeAnimation,
      in anchor: Entity,
      cameraPosition: SIMD3<Float>
    ) {
      switch animation {
      case .iris(let irisConfig):
        // Build legacy config - iris stores dome radius in baseSpeed
        var legacyConfig = DomeShatterConfig()
        legacyConfig.tessellatedFragmentCount = irisConfig.fragmentCount
        legacyConfig.baseSpeed = irisConfig.domeRadius

        start(
          fragmentCount: irisConfig.fragmentCount,
          radius: irisConfig.domeRadius,
          in: anchor,
          config: legacyConfig,
          algorithm: .iris,
          waveOrigin: nil,
          waveSpeed: 0,
          irisBladeCount: irisConfig.bladeCount,
          irisTwist: irisConfig.twistDegrees,
          irisOpenDuration: irisConfig.openDuration,
          cameraPosition: cameraPosition
        )
        // Handle iris-specific post-setup
        setSeamRibbonVisible(irisConfig.showSeamRibbons)
      }
    }

    // MARK: - Legacy Start API (used internally and by other engines until migrated)

    /// Start GPU-driven shatter with specified algorithm
    func start(
      fragmentCount targetCount: Int,
      radius: Float,
      in anchor: Entity,
      config: DomeShatterConfig,
      algorithm: DomeCollapseAlgorithm = .explode,
      waveOrigin: SIMD3<Float>?,
      waveSpeed: Float,
      cannonPower: Float = 0.0,
      rippleFrequency: Float = 5.0,
      rippleAmplitude: Float = 0.03,
      rippleSpeed: Float = 0.2,
      collapseSpeed: Float = 0.3,
      irisBladeCount: Int = 12,
      irisTwist: Float = 0.0,
      irisOpenDuration: Float = 4.0,
      cameraPosition: SIMD3<Float>,
      doubleSided: Bool = true
    ) {
      guard !isActive else { return }

      isActive = true
      currentAlgorithm = algorithm

      // Compute tessellation segments (same formula as generateTessellatedDome)
      let segments = max(4, Int(sqrt(Double(targetCount))))
      let latSegments = segments / 2
      let lonSegments = segments

      // Actual triangle count from tessellation
      let actualCount = lonSegments + (latSegments - 1) * lonSegments * 2
      fragmentCount = actualCount

      // Create mesh using GPU compute
      guard let generator = meshGenerator,
            let mesh = generator.generateMesh(
              latSegments: latSegments,
              lonSegments: lonSegments,
              radius: radius
            ) else {
        gpuLog.error("Failed to create mesh")
        isActive = false
        return
      }

      // Create header-only texture (lookup tables + dome/wave params + algorithm ID)
      guard let dataTex = createDataTexture(
        config: config,
        algorithm: algorithm,
        radius: radius,
        latSegments: latSegments,
        lonSegments: lonSegments,
        waveOrigin: waveOrigin,
        waveSpeed: waveSpeed,
        cannonPower: cannonPower,
        rippleFrequency: rippleFrequency,
        rippleAmplitude: rippleAmplitude,
        rippleSpeed: rippleSpeed,
        collapseSpeed: collapseSpeed,
        irisBladeCount: irisBladeCount,
        irisTwist: irisTwist,
        irisOpenDuration: irisOpenDuration
      ) else {
        gpuLog.error("Failed to create texture")
        isActive = false
        return
      }
      dataTexture = dataTex

      // Create material
      guard let material = createGPUMaterial(
        dataTexture: dataTex,
        algorithm: algorithm,
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

      // Create seam ribbon for iris algorithm
      if algorithm == .iris, irisBladeCount > 0 {
        if let ribbonMesh = createSeamRibbonMesh(bladeCount: irisBladeCount, segmentsPerArc: 64),
           let ribbonMaterial = createSeamRibbonMaterial(dataTexture: dataTex, cameraPosition: cameraPosition) {
          let ribbonEntity = ModelEntity(mesh: ribbonMesh, materials: [ribbonMaterial])
          anchor.addChild(ribbonEntity)
          seamRibbonEntity = ribbonEntity
        }
      }

      // Initialize at time 0
      currentTime = 0
      currentCameraPosition = cameraPosition
      updateMaterial()
    }

    // MARK: - Seam Ribbon Mesh

    /// Creates ribbon mesh for iris blade seams
    /// UV encoding: x = arcT (0-1), y = bladeIndex + widthSign*0.25
    private func createSeamRibbonMesh(bladeCount: Int, segmentsPerArc: Int) -> MeshResource? {
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var uvs: [SIMD2<Float>] = []
      var indices: [UInt32] = []

      // For each blade boundary, create a ribbon strip
      for blade in 0..<bladeCount {
        let bladeF = Float(blade)

        // Create quad strip along the arc
        for seg in 0..<segmentsPerArc {
          let t0 = Float(seg) / Float(segmentsPerArc)
          let t1 = Float(seg + 1) / Float(segmentsPerArc)

          // Four corners of this quad (positions at origin - shader moves them)
          // Left edge: widthSign encoded as 0.0 in UV.y fraction
          // Right edge: widthSign encoded as 0.5 in UV.y fraction
          let baseIdx = UInt32(positions.count)

          // Vertex 0: t0, left edge
          positions.append(SIMD3<Float>(0, 0, 0))
          normals.append(SIMD3<Float>(0, 1, 0))
          uvs.append(SIMD2<Float>(t0, bladeF + 0.0))

          // Vertex 1: t0, right edge
          positions.append(SIMD3<Float>(0, 0, 0))
          normals.append(SIMD3<Float>(0, 1, 0))
          uvs.append(SIMD2<Float>(t0, bladeF + 0.5))

          // Vertex 2: t1, left edge
          positions.append(SIMD3<Float>(0, 0, 0))
          normals.append(SIMD3<Float>(0, 1, 0))
          uvs.append(SIMD2<Float>(t1, bladeF + 0.0))

          // Vertex 3: t1, right edge
          positions.append(SIMD3<Float>(0, 0, 0))
          normals.append(SIMD3<Float>(0, 1, 0))
          uvs.append(SIMD2<Float>(t1, bladeF + 0.5))

          // Two triangles for the quad
          // Triangle 1: 0, 1, 2
          indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2])
          // Triangle 2: 1, 3, 2
          indices.append(contentsOf: [baseIdx + 1, baseIdx + 3, baseIdx + 2])
        }
      }

      var desc = MeshDescriptor(name: "iris_seam_ribbon")
      desc.positions = MeshBuffers.Positions(positions)
      desc.normals = MeshBuffers.Normals(normals)
      desc.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
      desc.primitives = .triangles(indices)

      do {
        return try MeshResource.generate(from: [desc])
      } catch {
        gpuLog.error("Ribbon mesh generation failed: \(error)")
        return nil
      }
    }

    /// Creates material for seam ribbon
    private func createSeamRibbonMaterial(
      dataTexture: TextureResource,
      cameraPosition: SIMD3<Float>
    ) -> CustomMaterial? {
      guard let device = MTLCreateSystemDefaultDevice(),
            let library = device.makeDefaultLibrary() else {
        return nil
      }

      do {
        let geometryModifier = CustomMaterial.GeometryModifier(
          named: "irisSeamRibbonGeometryModifier",
          in: library
        )

        let surfaceShader = CustomMaterial.SurfaceShader(
          named: "irisSeamRibbonSurfaceShader",
          in: library
        )

        var material = try CustomMaterial(
          surfaceShader: surfaceShader,
          geometryModifier: geometryModifier,
          lightingModel: .lit
        )

        material.faceCulling = .none  // Double-sided ribbon
        material.custom.value = [0, cameraPosition.x, cameraPosition.y, cameraPosition.z]
        material.custom.texture = .init(dataTexture)

        return material
      } catch {
        gpuLog.error("Ribbon material creation failed: \(error)")
        return nil
      }
    }

    func stop() {
      entity?.removeFromParent()
      entity = nil
      seamRibbonEntity?.removeFromParent()
      seamRibbonEntity = nil
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
        animation: DomeShatterVisibilityAdapter(texture: mtlTexture, fragmentCount: count, algorithm: currentAlgorithm),
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

      // Update ribbon material too
      if let ribbonEntity = seamRibbonEntity,
         var ribbonMaterial = ribbonEntity.model?.materials.first as? CustomMaterial {
        ribbonMaterial.custom.value = [
          currentTime, currentCameraPosition.x, currentCameraPosition.y, currentCameraPosition.z,
        ]
        ribbonEntity.model?.materials = [ribbonMaterial]
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
      algorithm: DomeCollapseAlgorithm,
      radius: Float,
      latSegments: Int,
      lonSegments: Int,
      waveOrigin: SIMD3<Float>?,
      waveSpeed: Float,
      cannonPower: Float,
      rippleFrequency: Float,
      rippleAmplitude: Float,
      rippleSpeed: Float,
      collapseSpeed: Float,
      irisBladeCount: Int = 12,
      irisTwist: Float = 0.0,
      irisOpenDuration: Float = 4.0
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
      //   Col 7 (row 0): algorithmID (R channel)

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

          // Col 7: Algorithm ID (R), Cannon Power (GB as 16-bit)
          let cannonPower16 = encode16bit(cannonPower, min: 0.0, max: 5.0)
          pixels.append(UInt8(algorithm.rawValue))
          pixels.append(UInt8((cannonPower16 >> 8) & 0xFF))
          pixels.append(UInt8(cannonPower16 & 0xFF))
          pixels.append(0)

          // Col 8: baseGravity (RG), gravityMin (BA)
          let baseGravity16 = encode16bit(config.baseGravity, min: 0.0, max: 2.0)
          let gravityMin16 = encode16bit(config.gravityMin, min: 0.0, max: 2.0)
          pixels.append(UInt8((baseGravity16 >> 8) & 0xFF))
          pixels.append(UInt8(baseGravity16 & 0xFF))
          pixels.append(UInt8((gravityMin16 >> 8) & 0xFF))
          pixels.append(UInt8(gravityMin16 & 0xFF))

          // Col 9: gravityMax (RG), spinRateMin (BA)
          let gravityMax16 = encode16bit(config.gravityMax, min: 0.0, max: 2.0)
          let spinRateMin16 = encode16bit(config.spinRateMin, min: 0.0, max: 20.0)
          pixels.append(UInt8((gravityMax16 >> 8) & 0xFF))
          pixels.append(UInt8(gravityMax16 & 0xFF))
          pixels.append(UInt8((spinRateMin16 >> 8) & 0xFF))
          pixels.append(UInt8(spinRateMin16 & 0xFF))

          // Col 10: spinRateMax (RG), baseSpeed (BA)
          let spinRateMax16 = encode16bit(config.spinRateMax, min: 0.0, max: 20.0)
          let baseSpeed16 = encode16bit(config.baseSpeed, min: -2.0, max: 2.0)
          pixels.append(UInt8((spinRateMax16 >> 8) & 0xFF))
          pixels.append(UInt8(spinRateMax16 & 0xFF))
          pixels.append(UInt8((baseSpeed16 >> 8) & 0xFF))
          pixels.append(UInt8(baseSpeed16 & 0xFF))

          // Col 11: spreadAngle (RG), upwardBias (BA)
          let spreadAngle16 = encode16bit(config.spreadAngle, min: 0.0, max: 2.0)
          let upwardBias16 = encode16bit(config.upwardBias, min: -2.0, max: 2.0)
          pixels.append(UInt8((spreadAngle16 >> 8) & 0xFF))
          pixels.append(UInt8(spreadAngle16 & 0xFF))
          pixels.append(UInt8((upwardBias16 >> 8) & 0xFF))
          pixels.append(UInt8(upwardBias16 & 0xFF))

          // Col 12: waveFrequency (RG), waveAmplitude (BA) - for ripple algorithm
          let waveFreq16 = encode16bit(rippleFrequency, min: 1.0, max: 10.0)
          let waveAmp16 = encode16bit(rippleAmplitude, min: 0.0, max: 0.2)
          pixels.append(UInt8((waveFreq16 >> 8) & 0xFF))
          pixels.append(UInt8(waveFreq16 & 0xFF))
          pixels.append(UInt8((waveAmp16 >> 8) & 0xFF))
          pixels.append(UInt8(waveAmp16 & 0xFF))

          // Col 13: collapseSpeed (RG), rippleSpeed (BA) - for ripple algorithm
          let collapseSpeed16 = encode16bit(collapseSpeed, min: 0.0, max: 2.0)
          let rippleSpeed16 = encode16bit(rippleSpeed, min: 0.0, max: 2.0)
          pixels.append(UInt8((collapseSpeed16 >> 8) & 0xFF))
          pixels.append(UInt8(collapseSpeed16 & 0xFF))
          pixels.append(UInt8((rippleSpeed16 >> 8) & 0xFF))
          pixels.append(UInt8(rippleSpeed16 & 0xFF))

          // Col 14: irisBladeCount (RG), irisOpenDuration (BA) - for iris algorithm
          let irisBlades16 = UInt16(clamping: irisBladeCount)
          let irisOpenDuration16 = encode16bit(irisOpenDuration, min: 0.1, max: 10.0)
          pixels.append(UInt8((irisBlades16 >> 8) & 0xFF))
          pixels.append(UInt8(irisBlades16 & 0xFF))
          pixels.append(UInt8((irisOpenDuration16 >> 8) & 0xFF))
          pixels.append(UInt8(irisOpenDuration16 & 0xFF))

          // Col 15: reserved (RG), irisTwist (BA) - for iris algorithm
          let irisTwist16 = encode16bit(irisTwist, min: -180.0, max: 180.0)
          pixels.append(128)  // reserved
          pixels.append(128)  // reserved
          pixels.append(UInt8((irisTwist16 >> 8) & 0xFF))
          pixels.append(UInt8(irisTwist16 & 0xFF))

          // Cols 16+: padding
          for _ in 16..<width {
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
      algorithm: DomeCollapseAlgorithm,
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
        // Geometry modifier for physics - selected by algorithm
        let geometryModifier = CustomMaterial.GeometryModifier(
          named: algorithm.geometryModifierName,
          in: library
        )

        // Surface shader - selected by algorithm
        let surfaceShader = CustomMaterial.SurfaceShader(
          named: algorithm.surfaceShaderName,
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
    let algorithm: DomeCollapseAlgorithm

    var visibilityKernelName: String { algorithm.visibilityKernelName }

    func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder) {
      // Buffer 2: fragment count (buffer 0 = anyVisible, buffer 1 = time)
      var count = UInt32(fragmentCount)
      encoder.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 2)

      // Texture 0: data texture
      encoder.setTexture(texture, index: 0)
    }
  }

