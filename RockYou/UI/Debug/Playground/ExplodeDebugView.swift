// ExplodeDebugView.swift
// RockYou
//
// Debug view for explode dome shatter effect.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct ExplodeDebugView: View {
  var body: some View {
    MetalDebugView(
      engine: ExplodeEngine(),
      config: ExplodeEngine.config,
      timeRange: ExplodeEngine.timeRange,
      makeDefaultEngine: { ExplodeEngine() }
    )
  }
}

#Preview("Explode") {
  ExplodeDebugView()
    .frame(width: 900, height: 700)
}
