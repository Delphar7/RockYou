// ShaderRunTemplate.swift — Copy-and-customize template for Metal compute debugging.
//
// Usage:
//   1. cp tools/ShaderCLI/ShaderRunTemplate.swift /tmp/my_debug.swift
//   2. Edit the CUSTOMIZE sections below
//   3. Build the metallib: ./tools/ShaderCLI/build_metallib.sh
//   4. Run: swift /tmp/my_debug.swift
//
// Struct layout rules (Swift ↔ Metal):
//   Metal int    → Swift Int32        (4 bytes)
//   Metal float  → Swift Float        (4 bytes)
//   Metal float2 → Swift SIMD2<Float> (8 bytes)
//   Metal float3 → Swift SIMD3<Float> (16 bytes stride! 12 bytes size, padded to 16)
//   Metal float4 → Swift SIMD4<Float> (16 bytes)
//
// Verify with: MemoryLayout<YourStruct>.stride — must match Metal sizeof().

import Metal
import simd

// ---------------------------------------------------------------------------
// CUSTOMIZE: Params struct — must match the Metal kernel's constant buffer layout
// ---------------------------------------------------------------------------
struct Params {
  var count: Int32
  var radius: Float
  var threshold: Float
  // ... add fields to match your Metal struct
}

// ---------------------------------------------------------------------------
// CUSTOMIZE: Output struct — must match the Metal kernel's output buffer element
// ---------------------------------------------------------------------------
// For simple outputs (e.g., float3 positions), you can use SIMD3<Float> directly
// instead of defining a struct.
struct OutputElement {
  var x: Float
  var y: Float
  var z: Float
  var flag: Int32
}

func run() {
  // --- Metal setup ---
  guard let device = MTLCreateSystemDefaultDevice() else {
    print("ERROR: No Metal device available")
    return
  }

  let libPath = "/tmp/metal_build/RockYou.metallib"
  guard let library = try? device.makeLibrary(filepath: libPath) else {
    print("ERROR: Can't load \(libPath) — run build_metallib.sh first")
    return
  }

  // CUSTOMIZE: kernel function name
  let kernelName = "myComputeKernel"

  guard let function = library.makeFunction(name: kernelName) else {
    print("ERROR: '\(kernelName)' not found in metallib")
    print("Available functions:")
    for name in library.functionNames { print("  \(name)") }
    return
  }

  guard let pipeline = try? device.makeComputePipelineState(function: function),
        let queue = device.makeCommandQueue() else {
    print("ERROR: Failed to create pipeline or command queue")
    return
  }

  // --- Parameters ---
  // CUSTOMIZE: set your parameter values
  var params = Params(
    count: 10,
    radius: 1.0,
    threshold: 0.3
  )

  // CUSTOMIZE: number of output elements (must match kernel grid size)
  let outputCount = Int(params.count)

  // --- Allocate output buffer ---
  let bufSize = outputCount * MemoryLayout<OutputElement>.stride
  guard let outputBuffer = device.makeBuffer(length: bufSize, options: .storageModeShared) else {
    print("ERROR: Can't allocate output buffer (\(bufSize) bytes)")
    return
  }

  // --- Dispatch compute kernel ---
  guard let cmdBuf = queue.makeCommandBuffer(),
        let encoder = cmdBuf.makeComputeCommandEncoder() else {
    print("ERROR: Can't create command buffer/encoder")
    return
  }

  encoder.setComputePipelineState(pipeline)
  withUnsafeBytes(of: &params) { raw in
    encoder.setBytes(raw.baseAddress!, length: raw.count, index: 0)
  }
  encoder.setBuffer(outputBuffer, offset: 0, index: 1)

  let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
  encoder.dispatchThreads(
    MTLSize(width: outputCount, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
  )
  encoder.endEncoding()

  cmdBuf.commit()
  cmdBuf.waitUntilCompleted()

  if let error = cmdBuf.error {
    print("ERROR: Compute dispatch failed: \(error)")
    return
  }

  // --- Read back results ---
  let ptr = outputBuffer.contents().bindMemory(to: OutputElement.self, capacity: outputCount)

  // CUSTOMIZE: print or process results
  print("=== RESULTS ===")
  print("Output element stride: \(MemoryLayout<OutputElement>.stride) bytes")
  print()
  for i in 0..<outputCount {
    let r = ptr[i]
    print("[\(i)] x=\(r.x) y=\(r.y) z=\(r.z) flag=\(r.flag)")
  }
}

run()
