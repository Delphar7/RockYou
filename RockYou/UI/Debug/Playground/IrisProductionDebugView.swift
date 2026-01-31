// IrisProductionDebugView.swift
// RockYou/UI/Debug/Playground
//
// Production debug view for iris mechanism.
// Uses RealityDebugView with IrisEngine/IrisContent.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

struct IrisProductionDebugView: View {
  var body: some View {
    RealityDebugView(
      engine: IrisEngine(),
      config: IrisEngine.propertyConfig,
      makeDefaultEngine: { IrisEngine() }
    )
  }
}

#Preview("Iris") {
  IrisProductionDebugView()
    .frame(width: 950, height: 700)
}
