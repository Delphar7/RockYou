// RippleDebugView.swift
// RockYou
//
// Debug view for ripple dome shatter effect.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct RippleDebugView: View {
  var body: some View {
    MetalDebugView(
      engine: RippleEngine(),
      config: RippleEngine.config,
      timeRange: RippleEngine.timeRange,
      makeDefaultEngine: { RippleEngine() }
    )
  }
}

#Preview("Ripple") {
  RippleDebugView()
    .frame(width: 900, height: 700)
}
