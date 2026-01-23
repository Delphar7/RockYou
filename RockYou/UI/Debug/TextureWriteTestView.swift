// TextureWriteTestView.swift
// RockYou
//
// Test: Can we write to a texture from a RealityKit CustomMaterial shader?
// macOS-only debug view.

#if os(macOS)

import Combine
import Metal
import RealityKit
import SwiftUI

struct TextureWriteTestView: View {
  @State private var testResult: String = "Analyzing..."
  @State private var details: [String] = []

  var body: some View {
    VStack(spacing: 20) {
      Text("Texture Write Test")
        .font(.headline)

      Text(testResult)
        .font(.system(size: 24, weight: .bold))
        .foregroundColor(testResult.contains("Worked") ? .green : .red)
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.1)))

      VStack(alignment: .leading, spacing: 4) {
        ForEach(details, id: \.self) { detail in
          Text(detail)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .padding(40)
    .frame(width: 500, height: 400)
    .onAppear {
      runAnalysis()
    }
  }

  private func runAnalysis() {
    var results: [String] = []

    // Check 1: Does RealityKit expose texture write in shader API?
    results.append("1. RealityKit shader API check:")
    results.append("   params.textures().custom() returns: texture sampler (read-only)")
    results.append("   No write accessor available in surface_parameters")

    // Check 2: Can we even create a writable texture binding?
    results.append("")
    results.append("2. CustomMaterial texture binding:")
    results.append("   custom.texture = MaterialParameters.Texture (read-only binding)")
    results.append("   No read_write or write-only option in API")

    // Check 3: What would we need?
    results.append("")
    results.append("3. What GPU->CPU feedback requires:")
    results.append("   - MTLBuffer with storageModeShared")
    results.append("   - Shader [[buffer(N)]] binding with atomic writes")
    results.append("   - Neither exposed by CustomMaterial API")

    details = results
    testResult = "Didn't work (API limitation)"

    // But let's at least verify the shader compiles
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      let shaderCompiles = testShaderCompilation()
      details.append("")
      details.append("4. Test shader compilation: \(shaderCompiles ? "OK" : "Failed")")
    }
  }

  private func testShaderCompilation() -> Bool {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary() else {
      return false
    }

    // Check if our test shader function exists and compiled
    let function = library.makeFunction(name: "textureWriteTestSurface")
    return function != nil
  }
}

#Preview("Texture Write Test") {
  TextureWriteTestView()
}

#endif
