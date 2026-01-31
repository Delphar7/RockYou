// BloomingFlowerDebugView.swift
// RockYou/UI/Debug/Playground
//
// Debug view for blooming flower blade animation.
// Uses RealityDebugView with BloomingFlowerEngine for SceneView rendering.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct BloomingFlowerDebugView: View {
  var body: some View {
    RealityDebugView(
      engine: BloomingFlowerEngine(),
      config: BloomingFlowerEngine.propertyConfig,
      makeDefaultEngine: { BloomingFlowerEngine() }
    )
  }
}

#Preview("Blooming Flower") {
  BloomingFlowerDebugView()
    .frame(width: 900, height: 650)
}
