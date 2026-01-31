// seam_debug.swift — Call halfSpaceComputeSeamArcs to evaluate seam arc geometry.
//
// Dispatches the seam arc compute kernel and prints per-blade results:
// valid point count, first/last positions, Y range.
// Also runs a comparison at elevation=0 and dumps the full arc for blade 0.
//
// Prerequisites: ../build_metallib.sh
// Usage: swift tools/ShaderCLI/examples/seam_debug.swift

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

func run() {
  guard let device = MTLCreateSystemDefaultDevice() else {
    print("ERROR: No Metal device"); return
  }

  let libPath = "/tmp/metal_build/RockYou.metallib"
  guard let library = try? device.makeLibrary(filepath: libPath) else {
    print("ERROR: Can't load \(libPath) — run build_metallib.sh first"); return
  }

  guard let seamFunc = library.makeFunction(name: "halfSpaceComputeSeamArcs"),
        let seamPipeline = try? device.makeComputePipelineState(function: seamFunc),
        let queue = device.makeCommandQueue() else {
    print("ERROR: Pipeline setup failed"); return
  }

  // --- Parameters ---
  let bladeCount: Int32 = 6
  let arcPointCount: Int32 = 65

  var params = HalfSpaceComputeParams(
    bladeCount: bladeCount,
    domeRadius: 1.0,
    aperture: 0.3,
    tilt: 0.0,
    elevation: 30.0 * .pi / 180.0,
    arcPointCount: arcPointCount,
    latSteps: 16,
    lonSteps: 32
  )

  let seamCount = Int(bladeCount) * Int(arcPointCount)
  let seamBufSize = seamCount * MemoryLayout<SIMD3<Float>>.stride

  // --- Helper: dispatch and return results ---
  func dispatchSeamArcs(_ p: inout HalfSpaceComputeParams) -> [SIMD3<Float>]? {
    guard let buf = device.makeBuffer(length: seamBufSize, options: .storageModeShared),
          let cmdBuf = queue.makeCommandBuffer(),
          let enc = cmdBuf.makeComputeCommandEncoder() else { return nil }

    enc.setComputePipelineState(seamPipeline)
    withUnsafeBytes(of: &p) { raw in
      enc.setBytes(raw.baseAddress!, length: raw.count, index: 0)
    }
    enc.setBuffer(buf, offset: 0, index: 1)
    let tpg = min(seamPipeline.maxTotalThreadsPerThreadgroup, 256)
    enc.dispatchThreads(MTLSize(width: seamCount, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: tpg, height: 1, depth: 1))
    enc.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    if let err = cmdBuf.error { print("ERROR: \(err)"); return nil }

    let ptr = buf.contents().bindMemory(to: SIMD3<Float>.self, capacity: seamCount)
    return Array(UnsafeBufferPointer(start: ptr, count: seamCount))
  }

  // --- Print blade summary ---
  func printBladeSummary(_ results: [SIMD3<Float>], label: String) {
    print("=== \(label) ===")
    for blade in 0..<Int(bladeCount) {
      let start = blade * Int(arcPointCount)
      let end = start + Int(arcPointCount)
      let valid = (start..<end).compactMap { results[$0].y > -999 ? results[$0] : nil }

      if valid.isEmpty {
        print("Blade \(blade): NO VALID POINTS")
      } else {
        let first = valid.first!, last = valid.last!
        let minY = valid.map(\.y).min()!, maxY = valid.map(\.y).max()!
        let f = { (v: Float) -> String in String(format: "%.4f", v) }
        print("Blade \(blade): \(valid.count)/\(arcPointCount) valid")
        print("  first: (\(f(first.x)), \(f(first.y)), \(f(first.z)))")
        print("  last:  (\(f(last.x)), \(f(last.y)), \(f(last.z)))")
        print("  Y range: [\(f(minY)), \(f(maxY))]")
        if minY > 0.01 {
          print("  *** ARC DOES NOT REACH Y=0 ***")
        }
      }
    }
  }

  // --- Run at configured elevation ---
  guard let results = dispatchSeamArcs(&params) else { return }
  let elevDeg = params.elevation * 180.0 / Float.pi
  printBladeSummary(results, label: "SEAM ARC RESULTS (elevation=\(String(format: "%.0f", elevDeg))deg)")

  // --- Comparison at elevation=0 ---
  print()
  var params0 = params
  params0.elevation = 0
  guard let results0 = dispatchSeamArcs(&params0) else { return }
  printBladeSummary(results0, label: "COMPARISON: elevation=0")

  // --- Full arc dump for blade 0 ---
  print()
  print("=== BLADE 0 FULL ARC (elevation=\(String(format: "%.0f", elevDeg))deg) ===")
  for i in 0..<Int(arcPointCount) {
    let p = results[i]
    let valid = p.y > -999
    let t = Float(i) / Float(arcPointCount - 1)
    print("  arcT=\(String(format: "%.3f", t)) -> (\(String(format: "%+.4f", p.x)), \(String(format: "%+.4f", p.y)), \(String(format: "%+.4f", p.z))) \(valid ? "" : "INVALID")")
  }
}

run()
