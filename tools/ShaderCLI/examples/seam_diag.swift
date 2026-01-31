// seam_diag.swift — Call the halfSpaceSeamDiagnostics kernel to inspect intermediates.
//
// Demonstrates the "diagnostic kernel" pattern: add a custom compute kernel to your
// .metal file that writes intermediate algorithm values into a struct, then read them
// back from Swift to debug GPU math without printf.
//
// Prerequisites: ../build_metallib.sh
// Usage: swift tools/ShaderCLI/examples/seam_diag.swift

import Metal
import simd

// Must match HalfSpaceComputeParams in HalfSpaceIrisCompute.metal (32 bytes)
struct HalfSpaceComputeParams {
  var bladeCount: Int32
  var domeRadius: Float
  var aperture: Float
  var tilt: Float
  var elevation: Float
  var arcPointCount: Int32
  var latSteps: Int32
  var lonSteps: Int32
}

// Must match SeamDiagnostics in HalfSpaceIrisCompute.metal (16 floats = 64 bytes)
struct SeamDiagnostics {
  var thetaStart: Float
  var thetaEnd: Float
  var thetaSpan: Float
  var startY: Float
  var endY: Float
  var equatorEntryRaw: Float
  var u_y: Float
  var v_y: Float
  var alpha: Float
  var beta: Float
  var gamma: Float
  var ratio: Float
  var base: Float
  var delta: Float
  var r1: Float
  var r2: Float
}

func run() {
  guard let device = MTLCreateSystemDefaultDevice(),
        let library = try? device.makeLibrary(filepath: "/tmp/metal_build/RockYou.metallib"),
        let diagFunc = library.makeFunction(name: "halfSpaceSeamDiagnostics"),
        let pipeline = try? device.makeComputePipelineState(function: diagFunc),
        let queue = device.makeCommandQueue() else {
    print("ERROR: Metal setup failed — run build_metallib.sh first")
    return
  }

  let bladeCount: Int32 = 6
  var params = HalfSpaceComputeParams(
    bladeCount: bladeCount,
    domeRadius: 1.0,
    aperture: 0.3,
    tilt: 0.0,
    elevation: 30.0 * .pi / 180.0,
    arcPointCount: 65,
    latSteps: 16,
    lonSteps: 32
  )

  let count = Int(bladeCount)
  let bufSize = count * MemoryLayout<SeamDiagnostics>.stride

  guard let outBuf = device.makeBuffer(length: bufSize, options: .storageModeShared),
        let cmdBuf = queue.makeCommandBuffer(),
        let enc = cmdBuf.makeComputeCommandEncoder() else { return }

  enc.setComputePipelineState(pipeline)
  withUnsafeBytes(of: &params) { raw in
    enc.setBytes(raw.baseAddress!, length: raw.count, index: 0)
  }
  enc.setBuffer(outBuf, offset: 0, index: 1)

  let tpg = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
  enc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                      threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1))
  enc.endEncoding()
  cmdBuf.commit()
  cmdBuf.waitUntilCompleted()

  let ptr = outBuf.contents().bindMemory(to: SeamDiagnostics.self, capacity: count)

  // --- Print intermediate values per blade ---
  print("=== SEAM DIAGNOSTICS (elevation=30deg, aperture=0.3) ===")
  print("SeamDiagnostics stride: \(MemoryLayout<SeamDiagnostics>.stride) bytes")
  print()

  let f = { (v: Float) -> String in String(format: "%+.6f", v) }

  for i in 0..<count {
    let d = ptr[i]
    print("Blade \(i):")
    print("  Basis vectors:")
    print("    u_y:           \(f(d.u_y))")
    print("    v_y:           \(f(d.v_y))")
    print("  Equator intersection:")
    print("    alpha:         \(f(d.alpha))  (r * u.y)")
    print("    beta:          \(f(d.beta))  (r * v.y)")
    print("    gamma:         \(f(d.gamma))  (-center.y)")
    print("    ratio:         \(f(d.ratio))  (gamma / mag)")
    print("    base:          \(f(d.base))  (atan2(beta, alpha))")
    print("    delta:         \(f(d.delta))  (acos(clamp(ratio)))")
    print("  Roots:")
    print("    r1:            \(f(d.r1))  (base + delta)")
    print("    r2:            \(f(d.r2))  (base - delta)")
    print("    equatorEntry:  \(f(d.equatorEntryRaw))\(d.equatorEntryRaw < -999 ? " (FAILED)" : "")")

    let pickedR1 = abs(d.equatorEntryRaw - d.r1) < 0.001
    let pickedR2 = abs(d.equatorEntryRaw - d.r2) < 0.001
    print("    picked root:   \(pickedR1 ? "r1 (base+delta)" : pickedR2 ? "r2 (base-delta)" : "NEITHER")")

    print("  Arc span:")
    print("    thetaStart:    \(f(d.thetaStart))")
    print("    thetaEnd:      \(f(d.thetaEnd))")
    print("    thetaSpan:     \(f(d.thetaSpan))")
    print("    startY:        \(f(d.startY))")
    print("    endY:          \(f(d.endY))")

    if abs(d.startY) > 0.01 {
      print("    *** START DOES NOT REACH Y=0 ***")
    }
    print()
  }
}

run()
