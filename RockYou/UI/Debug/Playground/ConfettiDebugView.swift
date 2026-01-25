// ConfettiDebugView.swift
// RockYou
//
// Debug view for confetti dome shatter effect.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct ConfettiDebugView: View {
  var body: some View {
    MetalDebugView(
      engine: ConfettiEngine(),
      config: ConfettiEngine.config,
      timeRange: ConfettiEngine.timeRange,
      makeDefaultEngine: { ConfettiEngine() }
    )
  }
}

#Preview("Confetti") {
  ConfettiDebugView()
    .frame(width: 900, height: 700)
}
