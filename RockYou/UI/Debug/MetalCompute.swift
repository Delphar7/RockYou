// MetalCompute.swift
// RockYou/UI/Debug
//
// Reusable Metal compute helper for debug views.
// Dispatches compute kernels synchronously with cached pipelines.
// One-call API: function name, params struct, output element count → [R]?

import Metal
import os

private let log = Logger(subsystem: "com.rockyou", category: "MetalCompute")

@MainActor
final class MetalCompute {
  static let shared = MetalCompute()

  private let device: MTLDevice?
  private let commandQueue: MTLCommandQueue?
  private let library: MTLLibrary?
  private var pipelineCache: [String: MTLComputePipelineState] = [:]

  var isAvailable: Bool { device != nil }

  private init() {
    let dev = MTLCreateSystemDefaultDevice()
    self.device = dev
    self.commandQueue = dev?.makeCommandQueue()
    self.library = dev?.makeDefaultLibrary()
    if dev == nil {
      log.warning("No Metal device — compute kernels unavailable")
    }
  }

  /// Run a compute kernel synchronously.
  /// - Parameters:
  ///   - functionName: Metal kernel function name (cached after first use)
  ///   - params: Constant buffer struct (layout must match Metal)
  ///   - count: Number of output elements
  /// - Returns: Array of results, or nil if Metal unavailable or dispatch failed
  func execute<P, R>(_ functionName: String, params: P, count: Int) -> [R]? {
    guard let device, let commandQueue, let library else { return nil }

    let pipeline: MTLComputePipelineState
    if let cached = pipelineCache[functionName] {
      pipeline = cached
    } else {
      guard let function = library.makeFunction(name: functionName) else {
        log.error("Kernel '\(functionName)' not found in Metal library")
        return nil
      }
      do {
        let p = try device.makeComputePipelineState(function: function)
        pipelineCache[functionName] = p
        pipeline = p
      } catch {
        log.error("Failed to create pipeline for '\(functionName)': \(error)")
        return nil
      }
    }

    let outputSize = count * MemoryLayout<R>.stride
    guard outputSize > 0,
          let outputBuffer = device.makeBuffer(length: outputSize, options: .storageModeShared)
    else { return nil }

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else { return nil }

    encoder.setComputePipelineState(pipeline)
    withUnsafeBytes(of: params) { raw in
      encoder.setBytes(raw.baseAddress!, length: raw.count, index: 0)
    }
    encoder.setBuffer(outputBuffer, offset: 0, index: 1)

    let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    encoder.dispatchThreads(
      MTLSize(width: count, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
    )
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    if let error = commandBuffer.error {
      log.error("Compute '\(functionName)' failed: \(error)")
      return nil
    }

    let ptr = outputBuffer.contents().bindMemory(to: R.self, capacity: count)
    return Array(UnsafeBufferPointer(start: ptr, count: count))
  }
}
