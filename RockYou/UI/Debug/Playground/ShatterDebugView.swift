// ShatterDebugView.swift
// RockYou/UI/Debug/Playground
//
// Unified debug view for explode/confetti shatter effects.
// Uses RealityDebugView with ShatterEngine/ShatterContent.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct ShatterDebugView: View {
  var body: some View {
    RealityDebugView(
      engine: ShatterEngine(),
      config: ShatterEngine.propertyConfig,
      makeDefaultEngine: { ShatterEngine() }
    )
  }
}

#Preview("Shatter") {
  ShatterDebugView()
    .frame(width: 950, height: 700)
}
