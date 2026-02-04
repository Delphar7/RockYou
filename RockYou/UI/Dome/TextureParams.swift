// TextureParams.swift
// RockYou/UI/Dome
//
// Virtual byte buffer for passing parameters to Metal shaders via textures.
//
// Format: Each texture column stores 2 data bytes + 2 sentinel bytes:
//   [data, data, 0xDE, 0xED]
//
// Virtual byte N maps to:
//   Column = N / 2
//   Channel = N % 2 (0 = R, 1 = G)
//
// This format prevents ASTC texture compression on iOS A-series GPUs from
// corrupting parameter data (alpha=0 pixels get their RGB channels destroyed).
//
// 16-bit reads/writes must use even byte offsets. This is enforced at compile
// time on the Metal reader side via static_assert.

import CoreGraphics
import Foundation
import Metal
import os
import RealityKit

private let log = Logger(subsystem: "com.rockyou", category: "TextureParams")

// MARK: - Byte Offset Constants

/// Virtual byte offsets for texture parameters.
/// Must match `tex_param` constants in TextureParams.h.
enum TextureParam {
  // Shared dome params (all algorithms)
  static let radius = 0          // float16 [0.0, 2.0]
  static let latSegments = 2     // int16
  static let lonSegments = 4     // int16
  static let waveSpeed = 6       // float16 [0.0, 20.0]
  static let waveOriginX = 8     // float16 [-2.0, 2.0]
  static let waveOriginY = 10    // float16 [-2.0, 2.0]
  static let waveOriginZ = 12    // float16 [-2.0, 2.0]
  static let waveEnabled = 14    // int16

  // Algorithm identification
  static let algorithmID = 16    // int16
  static let cannonPower = 18    // float16 [0.0, 5.0]

  // Physics config (explode/confetti/ripple)
  static let baseGravity = 20    // float16 [0.0, 2.0]
  static let gravityMin = 22     // float16 [0.0, 2.0]
  static let gravityMax = 24     // float16 [0.0, 2.0]
  static let spinRateMin = 26    // float16 [0.0, 20.0]
  static let spinRateMax = 28    // float16 [0.0, 20.0]
  static let baseSpeed = 30      // float16 [-2.0, 2.0]
  static let spreadAngle = 32    // float16 [0.0, 2.0]
  static let upwardBias = 34     // float16 [-2.0, 2.0]

  // Ripple-specific
  static let waveFrequency = 36  // float16 [1.0, 10.0]
  static let waveAmplitude = 38  // float16 [0.0, 0.2]
  static let rippleSpeed = 40    // float16 [0.0, 2.0]

  // Iris-specific
  static let bladeCount = 42     // int16
  static let openDuration = 44   // float16 [0.1, 10.0]
  static let tilt = 46           // float16 [0.0, π/2]
  static let elevation = 48      // float16 [0.0, π/4]
}

// MARK: - Writer

/// Builds texture pixel data from virtual byte offsets.
///
/// Usage:
/// ```
/// var params = TextureParamWriter()
/// params.writeFloat16(0.8, at: TextureParam.radius, min: 0.0, max: 2.0)
/// params.writeInt16(86, at: TextureParam.latSegments)
/// let result = params.createTexture(name: "IrisData")
/// ```
struct TextureParamWriter {
  /// Sentinel bytes written to bytes 2-3 of every texture column.
  /// Prevents ASTC compression from corrupting data channels.
  static let sentinel: [UInt8] = [0xDE, 0xED]

  /// Texture width in pixels (columns). Each column holds 2 virtual bytes.
  static let textureWidth = 32

  /// Texture height in pixels (rows). Row 0 = header, rest = padding.
  static let textureHeight = 4096

  /// Virtual byte buffer. Index N maps to column N/2, channel N%2.
  private var data: [UInt8]

  init() {
    // Pre-fill with 0xAA so unused bytes are distinctive and non-zero
    data = [UInt8](repeating: 0xAA, count: Self.textureWidth * 2)
  }

  /// Write an 8-bit value at the given virtual byte offset.
  mutating func writeUInt8(_ value: UInt8, at offset: Int) {
    precondition(offset >= 0 && offset < data.count, "Offset \(offset) out of range")
    data[offset] = value
  }

  /// Write a 16-bit integer at an even virtual byte offset.
  mutating func writeInt16(_ value: Int, at offset: Int) {
    precondition(offset % 2 == 0, "16-bit writes must be at even offsets")
    precondition(offset >= 0 && offset + 1 < data.count, "Offset \(offset) out of range")
    let clamped = UInt16(clamping: value)
    data[offset] = UInt8((clamped >> 8) & 0xFF)
    data[offset + 1] = UInt8(clamped & 0xFF)
  }

  /// Write a float encoded as 16-bit within [min, max] at an even virtual byte offset.
  mutating func writeFloat16(_ value: Float, at offset: Int, min: Float, max: Float) {
    let normalized = (value - min) / (max - min)
    let clamped = Swift.max(0, Swift.min(1, normalized))
    let int16 = UInt16(clamped * 65535)
    writeInt16(Int(int16), at: offset)
  }

  // MARK: - Texture Creation

  struct TextureResult {
    let resource: TextureResource?
    let mtlTexture: MTLTexture?
  }

  /// Build pixel row for header, interleaving sentinel bytes.
  private func buildHeaderRow() -> [UInt8] {
    var pixels: [UInt8] = []
    pixels.reserveCapacity(Self.textureWidth * 4)
    for col in 0..<Self.textureWidth {
      let base = col * 2
      pixels.append(data[base])
      pixels.append(data[base + 1])
      pixels.append(contentsOf: Self.sentinel)
    }
    return pixels
  }

  /// Build a padding row (all non-zero, sentinel-safe).
  private static func buildPaddingRow() -> [UInt8] {
    var pixels: [UInt8] = []
    pixels.reserveCapacity(textureWidth * 4)
    for _ in 0..<textureWidth {
      pixels.append(0xAA)
      pixels.append(0xAA)
      pixels.append(contentsOf: sentinel)
    }
    return pixels
  }

  /// Create the full texture (header row + padding rows).
  func createTexture(name: String) -> TextureResult {
    let width = Self.textureWidth
    let height = Self.textureHeight

    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height * 4)

    // Row 0: header with encoded params
    pixels.append(contentsOf: buildHeaderRow())

    // Rows 1+: padding
    let paddingRow = Self.buildPaddingRow()
    for _ in 1..<height {
      pixels.append(contentsOf: paddingRow)
    }

    let bytesPerRow = width * 4
    let nsData = Data(pixels)
    guard let provider = CGDataProvider(data: nsData as CFData) else {
      log.error("CGDataProvider creation failed")
      return TextureResult(resource: nil, mtlTexture: nil)
    }

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
          ) else {
      log.error("CGImage creation failed")
      return TextureResult(resource: nil, mtlTexture: nil)
    }

    // Create Metal texture for compute shader
    var mtlTexture: MTLTexture?
    if let device = MTLCreateSystemDefaultDevice() {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
      )
      descriptor.usage = [.shaderRead]
      if let mtlTex = device.makeTexture(descriptor: descriptor) {
        let region = MTLRegion(
          origin: MTLOrigin(x: 0, y: 0, z: 0),
          size: MTLSize(width: width, height: height, depth: 1)
        )
        pixels.withUnsafeBytes { ptr in
          mtlTex.replace(region: region, mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }
        mtlTexture = mtlTex
      }
    }

    do {
      let resource = try TextureResource(image: cgImage, withName: name, options: .init(semantic: .raw))
      return TextureResult(resource: resource, mtlTexture: mtlTexture)
    } catch {
      log.error("Failed to create texture: \(error)")
      return TextureResult(resource: nil, mtlTexture: mtlTexture)
    }
  }
}
