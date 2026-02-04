// VisibilityChecker.swift
// RockYou
//
// GPU-based visibility checking for fragment animations.
// Runs a compute shader to check if any fragments are still visible,
// using the same physics as the geometry modifier.

import Metal

/// Result of a visibility check
enum VisibilityResult {
  case visible    // At least one fragment is still visible
  case allGone    // All fragments have fallen below clip plane
  case error      // Check failed (GPU error, etc.)
}

/// Protocol for animations that support GPU visibility checking
protocol VisibilityCheckable {
  /// The Metal function name for the visibility compute kernel
  var visibilityKernelName: String { get }

  /// Number of fragments to check
  var fragmentCount: Int { get }

  /// Encode animation-specific buffers/textures to the compute encoder
  /// Buffer 0 (anyVisible) and Buffer 1 (time) are handled by VisibilityChecker
  func encodeVisibilityParameters(encoder: MTLComputeCommandEncoder)
}

/// Checks fragment visibility using GPU compute shaders
final class VisibilityChecker {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let resultBuffer: MTLBuffer  // Atomic uint for visibility flag

  private var pipelineCache: [String: MTLComputePipelineState] = [:]

  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let buffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
    else {
      Log.error("VisibilityChecker", "Failed to create Metal resources")
      return nil
    }

    self.device = device
    self.commandQueue = queue
    self.resultBuffer = buffer
  }

  /// Check visibility for an animation.
  /// This is a synchronous call that waits for GPU completion.
  /// Call from a background thread if needed.
  func checkVisibility(animation: VisibilityCheckable, time: Float) -> VisibilityResult {
    // Get or create pipeline
    guard let pipeline = getPipeline(for: animation.visibilityKernelName) else {
      return .error
    }

    // Reset result buffer to 0 (no visible fragments)
    resultBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee = 0

    // Create command buffer
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      Log.error("VisibilityChecker", "Failed to create command buffer/encoder")
      return .error
    }

    encoder.setComputePipelineState(pipeline)

    // Buffer 0: Result (atomic uint)
    encoder.setBuffer(resultBuffer, offset: 0, index: 0)

    // Buffer 1: Time
    var timeValue = time
    encoder.setBytes(&timeValue, length: MemoryLayout<Float>.size, index: 1)

    // Let animation encode its specific parameters
    animation.encodeVisibilityParameters(encoder: encoder)

    // Dispatch
    let fragmentCount = animation.fragmentCount
    let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    let threadGroups = (fragmentCount + threadGroupSize - 1) / threadGroupSize

    encoder.dispatchThreadgroups(
      MTLSize(width: threadGroups, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
    )

    encoder.endEncoding()

    // Execute and wait
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    // Check for GPU error
    if commandBuffer.status == .error {
      Log.error("VisibilityChecker", "GPU error - \(commandBuffer.error?.localizedDescription ?? "unknown")")
      return .error
    }

    // Read result
    let visibleFlag = resultBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee
    return visibleFlag != 0 ? .visible : .allGone
  }

  /// Async version that doesn't block the calling thread
  func checkVisibilityAsync(
    animation: VisibilityCheckable,
    time: Float,
    completion: @escaping (VisibilityResult) -> Void
  ) {
    // Get or create pipeline
    guard let pipeline = getPipeline(for: animation.visibilityKernelName) else {
      completion(.error)
      return
    }

    // Reset result buffer
    resultBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee = 0

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      completion(.error)
      return
    }

    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(resultBuffer, offset: 0, index: 0)

    var timeValue = time
    encoder.setBytes(&timeValue, length: MemoryLayout<Float>.size, index: 1)

    animation.encodeVisibilityParameters(encoder: encoder)

    let fragmentCount = animation.fragmentCount
    let threadGroupSize = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
    let threadGroups = (fragmentCount + threadGroupSize - 1) / threadGroupSize

    encoder.dispatchThreadgroups(
      MTLSize(width: threadGroups, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadGroupSize, height: 1, depth: 1)
    )

    encoder.endEncoding()

    // Capture buffer reference for completion handler
    let buffer = self.resultBuffer

    commandBuffer.addCompletedHandler { cmd in
      if cmd.status == .error {
        completion(.error)
        return
      }
      let visibleFlag = buffer.contents().assumingMemoryBound(to: UInt32.self).pointee
      completion(visibleFlag != 0 ? .visible : .allGone)
    }

    commandBuffer.commit()
  }

  // MARK: - Private

  private func getPipeline(for kernelName: String) -> MTLComputePipelineState? {
    if let cached = pipelineCache[kernelName] {
      return cached
    }

    guard let library = device.makeDefaultLibrary(),
          let function = library.makeFunction(name: kernelName)
    else {
      Log.error("VisibilityChecker", "Kernel '\(kernelName)' not found in Metal library")
      return nil
    }

    do {
      let pipeline = try device.makeComputePipelineState(function: function)
      pipelineCache[kernelName] = pipeline
      return pipeline
    } catch {
      Log.error("VisibilityChecker", "Failed to create pipeline for '\(kernelName)': \(error)")
      return nil
    }
  }
}

// MARK: - Visibility Tracker

/// Encapsulates periodic visibility checking state.
/// Used by Content classes to avoid duplicating check-interval logic.
@MainActor
final class VisibilityTracker {
  private(set) var allFragmentsGone = false
  private var checker: VisibilityChecker?
  private var lastCheckTime: Float = -1
  private let checkInterval: Float = 0.5  // Check twice per second

  /// Check visibility if enough time has elapsed since the last check.
  /// Calls `onAllGone` (on the main thread) once when all fragments are gone.
  func checkIfNeeded(
    at time: Float,
    animation: VisibilityCheckable,
    onAllGone: @escaping () -> Void = {}
  ) {
    guard !allFragmentsGone else { return }
    guard time - lastCheckTime >= checkInterval else { return }
    lastCheckTime = time

    if checker == nil { checker = VisibilityChecker() }
    guard let checker else { return }

    checker.checkVisibilityAsync(animation: animation, time: time) { [weak self] result in
      DispatchQueue.main.async {
        guard let self, !self.allFragmentsGone else { return }
        if result == .allGone {
          self.allFragmentsGone = true
          onAllGone()
        }
      }
    }
  }
}
