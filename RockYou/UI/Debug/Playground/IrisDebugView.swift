// IrisDebugView.swift
// RockYou/UI/Debug/Playground
//
// Debug view for iris mechanism effect.
// Uses RealityDebugView with IrisEngine/IrisContent.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct IrisDebugView: View {
  var body: some View {
    RealityDebugView(
      engine: IrisEngine(),
      config: IrisEngine.propertyConfig,
      makeDefaultEngine: { IrisEngine() }
    )
  }
}

#Preview("Iris Mechanism") {
  IrisDebugView()
    .frame(width: 950, height: 700)
}
