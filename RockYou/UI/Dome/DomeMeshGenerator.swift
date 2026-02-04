// DomeMeshGenerator.swift
// RockYou/UI/Dome
//
// GPU-based dome mesh generation using Metal compute shaders.
// Generates tessellated dome vertices entirely on GPU.

import Foundation
import Metal
import os
import RealityKit

private let meshLog = Logger(subsystem: "com.rockyou", category: "DomeMesh")

/// Parameters passed to the compute shader (must match DomeComputeParams in Metal)
struct DomeComputeParams {
  var radius: Float
  var latSegments: UInt32
  var lonSegments: UInt32
  var totalTriangles: UInt32
}

/// GPU-based dome mesh generator using Metal compute shaders.
@MainActor
class DomeMeshGenerator {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let computePipeline: MTLComputePipelineState

  // Vertex stride must match DomeVertex in Metal (float3 + float3 + float2 = 32 bytes)
  private static let vertexStride = 32

  // MARK: - Tessellation Helpers

  /// Latitude segments for a given target fragment count.
  static func latSegments(for fragmentCount: Int) -> Int {
    let segments = max(4, Int(sqrt(Double(fragmentCount))))
    return segments / 2
  }

  /// Longitude segments for a given target fragment count.
  static func lonSegments(for fragmentCount: Int) -> Int {
    return max(4, Int(sqrt(Double(fragmentCount))))
  }

  /// Actual fragment (triangle) count produced by the tessellation.
  /// Must stay in sync with generateMesh() triangle layout.
  static func fragmentCount(latSegments: Int, lonSegments: Int) -> Int {
    return lonSegments + (latSegments - 1) * lonSegments * 2
  }

  init?() {
    guard let device = MTLCreateSystemDefaultDevice() else {
      Log.warn("DomeMesh", "FAIL: No Metal device available")
      meshLog.error("No Metal device available")
      return nil
    }

    guard let commandQueue = device.makeCommandQueue() else {
      Log.warn("DomeMesh", "FAIL: makeCommandQueue returned nil")
      meshLog.error("Failed to create command queue")
      return nil
    }
    self.commandQueue = commandQueue

    guard let library = device.makeDefaultLibrary() else {
      Log.warn("DomeMesh", "FAIL: makeDefaultLibrary returned nil")
      meshLog.error("Failed to load default Metal library")
      return nil
    }

    guard let computeFunction = library.makeFunction(name: "generateDomeVertices") else {
      Log.warn("DomeMesh", "FAIL: generateDomeVertices function not found in library")
      meshLog.error("Failed to find generateDomeVertices function")
      return nil
    }

    do {
      self.computePipeline = try device.makeComputePipelineState(function: computeFunction)
    } catch {
      Log.warn("DomeMesh", "FAIL: compute pipeline: \(error)")
      meshLog.error("Failed to create compute pipeline: \(error)")
      return nil
    }

    self.device = device
    Log.debug("DomeMesh", "Init OK: device=\(device.name)")
  }

  /// Generate dome mesh using GPU compute - NO COPY, direct GPU buffer usage
  /// - Parameters:
  ///   - latSegments: Number of latitude segments (rings from pole to equator)
  ///   - lonSegments: Number of longitude segments (slices around the dome)
  ///   - radius: Dome radius
  /// - Returns: MeshResource ready for use with ModelEntity, or nil on failure
  func generateMesh(
    latSegments: Int,
    lonSegments: Int,
    radius: Float
  ) -> MeshResource? {
    // Calculate triangle count (same formula as CPU path)
    let poleTriangles = lonSegments
    let bandTriangles = (latSegments - 1) * lonSegments * 2
    let totalTriangles = poleTriangles + bandTriangles
    let totalVertices = totalTriangles * 3

    // Set up compute parameters
    var params = DomeComputeParams(
      radius: radius,
      latSegments: UInt32(latSegments),
      lonSegments: UInt32(lonSegments),
      totalTriangles: UInt32(totalTriangles)
    )

    // Create LowLevelMesh first - RealityKit manages the buffers
    var descriptor = LowLevelMesh.Descriptor()
    descriptor.vertexCapacity = totalVertices
    descriptor.vertexAttributes = [
      .init(semantic: .position, format: .float3, offset: 0),
      .init(semantic: .normal, format: .float3, offset: 12),
      .init(semantic: .uv0, format: .float2, offset: 24),
    ]
    descriptor.vertexLayouts = [
      .init(bufferIndex: 0, bufferStride: Self.vertexStride),
    ]
    descriptor.indexCapacity = totalVertices
    descriptor.indexType = .uint32

    do {
      let mesh = try LowLevelMesh(descriptor: descriptor)

      guard let commandBuffer = commandQueue.makeCommandBuffer() else {
        meshLog.error("Failed to create command buffer")
        return nil
      }

      // Get buffer from LowLevelMesh and dispatch compute to fill it directly (zero-copy)
      let vertexBuffer = mesh.replace(bufferIndex: 0, using: commandBuffer)

      guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
        meshLog.error("Failed to create compute encoder")
        return nil
      }

      computeEncoder.setComputePipelineState(computePipeline)
      computeEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
      computeEncoder.setBytes(&params, length: MemoryLayout<DomeComputeParams>.size, index: 1)

      // Dispatch threads - one per vertex
      let threadsPerGroup = min(computePipeline.maxTotalThreadsPerThreadgroup, 256)
      let gridSize = MTLSize(width: totalVertices, height: 1, depth: 1)
      let groupSize = MTLSize(width: threadsPerGroup, height: 1, depth: 1)

      if device.supportsFamily(.apple4) || device.supportsFamily(.mac2) {
        // Non-uniform threadgroup dispatch (preferred)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
      } else {
        // Fallback for devices without non-uniform dispatch (e.g. iOS Simulator = Apple2)
        let groupCount = MTLSize(
          width: (totalVertices + threadsPerGroup - 1) / threadsPerGroup,
          height: 1,
          depth: 1
        )
        computeEncoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: groupSize)
      }
      computeEncoder.endEncoding()

      // Commit and wait for completion
      commandBuffer.commit()
      commandBuffer.waitUntilCompleted()

      if let error = commandBuffer.error {
        meshLog.error("Compute failed: \(error)")
        return nil
      }

      // Generate sequential indices (CPU side - but this is just integers, fast)
      mesh.withUnsafeMutableIndices { indexBuffer in
        let indices = indexBuffer.bindMemory(to: UInt32.self)
        for i in 0..<totalVertices {
          indices[i] = UInt32(i)
        }
      }

      // Set the mesh part
      let part = LowLevelMesh.Part(
        indexCount: totalVertices,
        topology: .triangle,
        bounds: BoundingBox(
          min: SIMD3<Float>(-radius, 0, -radius) * 1.1,
          max: SIMD3<Float>(radius, radius, radius) * 1.1
        )
      )
      mesh.parts.replaceAll([part])

      // Convert to MeshResource for use with ModelEntity
      return try MeshResource(from: mesh)

    } catch {
      meshLog.error("Failed to create LowLevelMesh: \(error)")
      return nil
    }
  }

}
