// RippleDebugView.swift
// RockYou/UI/Debug/Playground
//
// Debug view for ripple dome effect.
// Uses RealityDebugView with RippleEngine/RippleContent.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct RippleDebugView: View {
  var body: some View {
    RealityDebugView(
      engine: RippleEngine(),
      config: RippleEngine.propertyConfig,
      makeDefaultEngine: { RippleEngine() }
    )
  }
}

#Preview("Ripple") {
  RippleDebugView()
    .frame(width: 950, height: 700)
}
